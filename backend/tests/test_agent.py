"""The chat agent against a scripted fake client: no network, no key."""

import asyncio
import json
from datetime import date

import anthropic
import httpx2
import pytest
from app.agent import a2ui, loop, route
from app.agent.llm import ToolUse
from app.agent.numbers import allowed_values, unsupported
from app.agent.schema import AgentProfile, AgentRequest
from app.agent.tools import DATA_TOOLS, UI_TOOLS, tool_definitions
from app.config import settings
from app.main import app
from app.registry import REGISTRY
from app.widgets.catalog import CATALOG
from fake_llm import FakeClient, FakeTurn, demo_script
from fastapi.testclient import TestClient

client = TestClient(app)
PROFILE = AgentProfile(ward="URO", infection_type="uti", sex="F", age_band="65-74", onset="hospital")


def req(message="72-year-old woman, urology, urinary infection, hospital onset", **kw) -> AgentRequest:
    return AgentRequest(message=message, **kw)


def collect(request: AgentRequest, fake: FakeClient) -> list[tuple[str, dict]]:
    async def go():
        return [e async for e in loop.run(request, fake)]

    return asyncio.run(go())


def kinds(events) -> list[str]:
    return [e for e, _ in events]


def use(name, id_="t1", **inp) -> ToolUse:
    return ToolUse(id_, name, inp)


# ---- the fixed screen (the fake stream the UI builds against) ----------------------------------


def test_fixed_screen_streams_chips_organisms_coverage_then_one_line():
    events = collect(req(profile=PROFILE), FakeClient(demo_script))
    widgets = [d for e, d in events if e == "widget"]
    assert [w["widget"] for w in widgets] == ["ContextChips", "OrganismMix", "CoverageRanking"]
    assert all(w["params"]["ward"] == "URO" and w["params"]["infection_type"] == "uti" for w in widgets)
    assert all(w["params"]["as_of"] == "2026-09-27" for w in widgets)
    assert kinds(events).count("in_short") == 1 and kinds(events)[-1] == "done"
    assert events[-1][1]["ok"] is True
    header = [d for e, d in events if e == "header"][-1]
    assert header["profile"]["onset"] == "hospital"


def test_chips_arrive_before_the_turn_ends():
    """Widgets are sent as soon as their input is complete, not after the model's turn."""
    seen = []

    class Slow(FakeClient):
        async def turn(self, **kw):
            async for ev in super().turn(**kw):
                seen.append(type(ev).__name__)
                yield ev

    collect(req(profile=PROFILE), Slow(demo_script))
    assert seen.index("ToolUse") < seen.index("TurnEnd")


def test_as_of_comes_from_the_request_not_the_model():
    script = [FakeTurn([use("render_widget", widget="OrganismMix", params={"ward": "URO", "as_of": "2020-01-01"})]), FakeTurn(stop_reason="end_turn")]
    events = collect(req(as_of=date(2025, 6, 30)), FakeClient(lambda _: script))
    (w,) = [d for e, d in events if e == "widget"]
    assert w["params"]["as_of"] == "2025-06-30"


# ---- validation and the retry the model gets ---------------------------------------------------


def test_a_bad_widget_is_refused_and_the_model_can_correct_it():
    bad = FakeTurn([use("render_widget", "a", widget="NoSuchWidget", params={}), use("render_widget", "b", widget="OrganismMix", params={"ward": "MARS"})])
    good = FakeTurn([use("render_widget", "c", widget="OrganismMix", params={"ward": "URO"})])
    fake = FakeClient(lambda _: [bad, good, FakeTurn(stop_reason="end_turn")])
    events = collect(req(), fake)
    assert [d["widget"] for e, d in events if e == "widget"] == ["OrganismMix"]
    errors = [b for b in fake.calls[1]["messages"][-1]["content"] if b.get("is_error")]
    assert len(errors) == 2 and "unknown widget" in errors[0]["content"] and "bad params" in errors[1]["content"]


def test_every_tool_call_is_answered_in_one_user_message():
    t1 = FakeTurn([use("get_alerts", "a", ward="URO"), use("render_widget", "b", widget="OrganismMix", params={"ward": "URO"}), use("get_organisms", "c", ward="URO")])
    fake = FakeClient(lambda _: [t1, FakeTurn(stop_reason="end_turn")])
    collect(req(), fake)
    results = fake.calls[1]["messages"][-1]["content"]
    assert [r["tool_use_id"] for r in results] == ["a", "b", "c"]
    assert all(r["type"] == "tool_result" for r in results)
    assert "alerts" in results[0]["content"]  # a data tool really ran


def test_a_widget_is_never_placed_twice():
    same = {"widget": "OrganismMix", "params": {"ward": "URO"}}
    fake = FakeClient(lambda _: [FakeTurn([ToolUse("a", "render_widget", same), ToolUse("b", "render_widget", same)]), FakeTurn(stop_reason="end_turn")])
    assert kinds(collect(req(), fake)).count("widget") == 1


def test_a_data_tool_error_goes_back_to_the_model():
    t1 = FakeTurn([use("get_alert_detail", "a", alert_id="no-such-alert")])
    fake = FakeClient(lambda _: [t1, FakeTurn(stop_reason="end_turn")])
    events = collect(req(), fake)
    (r,) = fake.calls[1]["messages"][-1]["content"]
    assert r["is_error"] and "get_alert_detail failed" in r["content"]
    assert events[-1][1]["ok"] is True  # the stream carries on


# ---- the narrative may not contain numbers nobody supplied -------------------------------------


def test_summary_with_an_invented_number_is_rewritten_once():
    t1 = FakeTurn([use("get_organisms", "a", ward="URO", infection_type="uti")])
    t2 = FakeTurn([use("in_short", "b", text="E. coli causes 99 % of cases.")])
    t3 = FakeTurn([use("in_short", "c", text="E. coli is the most common cause here.")])
    fake = FakeClient(lambda _: [t1, t2, t3, FakeTurn(stop_reason="end_turn")])
    events = collect(req(), fake)
    assert [d["text"] for e, d in events if e == "in_short"] == ["E. coli is the most common cause here."]
    rejected = fake.calls[2]["messages"][-1]["content"][0]
    assert rejected["is_error"] and "99" in rejected["content"]


def test_a_second_invented_number_drops_the_text_and_the_app_shows_a_placeholder():
    t = lambda i: FakeTurn([use("in_short", f"s{i}", text="Resistance is 87 %.")])
    events = collect(req(), FakeClient(lambda _: [t(1), t(2), FakeTurn(stop_reason="end_turn")]))
    assert [d["text"] for e, d in events if e == "in_short"] == [None]


def test_numbers_from_tool_results_and_the_users_own_message_are_allowed():
    allowed = allowed_values([{"value": 0.376, "n": 44}, "72-year-old"])
    assert unsupported("38 % of 44 isolates, a 72-year-old", allowed) == []
    assert unsupported("41 % of 44", allowed) == ["41"]


# ---- failures become events, never a broken stream ---------------------------------------------


def test_a_refusal_becomes_an_error_event():
    events = collect(req(), FakeClient(lambda _: [FakeTurn(stop_reason="refusal")]))
    assert ("error", {"code": "refusal", "message": loop.REFUSAL_MESSAGE}) in events
    assert events[-1][1]["ok"] is False


def test_a_truncated_answer_is_an_error_event():
    events = collect(req(), FakeClient(lambda _: [FakeTurn([use("render_widget", widget="OrganismMix", params={})], stop_reason="max_tokens")]))
    assert [d["code"] for e, d in events if e == "error"] == ["too_long"]


def test_the_loop_stops_after_eight_iterations():
    forever = lambda _: FakeTurn([use("get_alerts", "x", ward="URO")])
    fake = FakeClient(lambda _: [forever] * 20)
    events = collect(req(), fake)
    assert len(fake.calls) == loop.MAX_ITERATIONS
    assert [d["code"] for e, d in events if e == "error"] == ["too_many_steps"]


@pytest.mark.parametrize(
    ("exc", "code"),
    [
        (anthropic.RateLimitError("slow down", response=httpx2.Response(429, request=httpx2.Request("POST", "http://x")), body=None), "rate_limited"),
        (anthropic.APITimeoutError(request=httpx2.Request("POST", "http://x")), "timeout"),
        (anthropic.APIConnectionError(request=httpx2.Request("POST", "http://x")), "unreachable"),
        (anthropic.InternalServerError("boom", response=httpx2.Response(500, request=httpx2.Request("POST", "http://x")), body=None), "upstream"),
        (anthropic.AuthenticationError("bad key", response=httpx2.Response(401, request=httpx2.Request("POST", "http://x")), body=None), "unavailable"),
        (RuntimeError("bug"), "internal"),
    ],
)
def test_api_failures_become_error_events(exc, code):
    class Broken:
        async def turn(self, **kw):
            raise exc
            yield  # pragma: no cover

    async def go():
        return [e async for e in loop.run(req(), Broken())]

    events = asyncio.run(go())
    assert [d["code"] for e, d in events if e == "error"] == [code]
    assert events[-1][0] == "done" and events[-1][1]["ok"] is False


def test_unparseable_tool_input_asks_the_turn_again_a_few_times_then_fails():
    class Flaky:
        calls = 0

        async def turn(self, **kw):
            Flaky.calls += 1
            raise ValueError("bad json")
            yield  # pragma: no cover

    async def go():
        return [e async for e in loop.run(req(), Flaky())]

    events = asyncio.run(go())
    assert Flaky.calls == loop.MAX_JSON_RETRIES + 1
    assert [d["code"] for e, d in events if e == "error"] == ["internal"]


# ---- clarifying questions ----------------------------------------------------------------------


def test_ask_user_sends_the_question_and_keeps_what_was_understood():
    ask = use("ask_user", "q", question="What kind of infection?", options=["Urinary tract", "Sepsis", "Wound infection"], understood={"ward": "URO", "sex": "F", "age_band": "65-74"})
    fake = FakeClient(lambda _: [FakeTurn([ask])])
    events = collect(req("woman, 72, urology"), fake)
    assert ("clarify", {"question": "What kind of infection?", "options": ["Urinary tract", "Sepsis", "Wound infection"]}) in events
    header = next(d for e, d in events if e == "header")
    assert header["profile"] == {"ward": "URO", "sex": "F", "age_band": "65-74"}
    assert len(fake.calls) == 1  # the turn ends there: no round trip while the user answers


# ---- the prompt and the tools ------------------------------------------------------------------


def test_the_cached_prefix_does_not_change_between_requests():
    f1, f2 = FakeClient(demo_script), FakeClient(demo_script)
    collect(req(as_of=date(2025, 6, 30), profile=PROFILE), f1)
    collect(req("a different question", as_of=date(2026, 1, 5), role="lab"), f2)
    assert f1.calls[0]["system"] == f2.calls[0]["system"]
    assert json.dumps(f1.calls[0]["tools"]) == json.dumps(f2.calls[0]["tools"])
    assert "2025-06-30" in f1.calls[0]["messages"][0]["content"] and "2025-06-30" not in f1.calls[0]["system"]


def test_the_tools_are_the_registry_functions_and_the_catalog():
    tools = {t["name"]: t for t in tool_definitions()}
    assert set(tools) == set(DATA_TOOLS) | set(UI_TOOLS)
    assert all(name in REGISTRY for name in DATA_TOOLS)
    assert all(REGISTRY[n].method == "GET" for n in DATA_TOOLS)  # read-only: nothing here can write
    assert tools["render_widget"]["input_schema"]["properties"]["widget"]["enum"] == sorted(CATALOG)
    assert all("as_of" not in tools[n]["input_schema"]["properties"] for n in DATA_TOOLS)  # the replay slider decides


# ---- the HTTP route ----------------------------------------------------------------------------


def parse_sse(text: str) -> list[tuple[str, dict]]:
    out = []
    for block in text.strip().split("\n\n"):
        lines = [ln for ln in block.split("\n") if not ln.startswith(":")]
        if lines:
            out.append((lines[0].removeprefix("event: "), json.loads(lines[1].removeprefix("data: "))))
    return out


@pytest.fixture
def scripted(monkeypatch):
    """The route plays the fixed doctor screen instead of calling Claude."""
    monkeypatch.setattr(route, "make_client", lambda: FakeClient(demo_script))


def test_the_route_streams_server_sent_events_with_the_right_headers(scripted):
    r = client.post("/v1/agent/screen", json={"message": "describe", "profile": PROFILE.model_dump()})
    assert r.status_code == 200 and r.headers["content-type"].startswith("text/event-stream")
    assert r.headers["cache-control"] == "no-cache" and r.headers["x-accel-buffering"] == "no"
    events = parse_sse(r.text)
    assert [c["component"] for c in a2ui_parts(events)] == ["ContextChips", "OrganismMix", "CoverageRanking", "InShort"]
    assert events[-1][0] == "done"


def a2ui_parts(events) -> list[dict]:
    """The parts of the answer surface in order, without the root."""
    return [c for e, d in events if e == "a2ui" and "updateComponents" in d for c in d["updateComponents"]["components"] if c["id"] != "root"]


def test_the_answer_is_one_a2ui_surface_built_part_by_part(scripted):
    events = parse_sse(client.post("/v1/agent/screen", json={"message": "describe", "profile": PROFILE.model_dump()}).text)
    assert not {"widget", "in_short", "clarify"} & set(kinds(events))
    messages = [d for e, d in events if e == "a2ui"]
    assert all(m["version"] == "v0.9" for m in messages)
    create = messages[0]["createSurface"]
    assert create["catalogId"] == a2ui.CATALOG_ID
    assert all(m["updateComponents"]["surfaceId"] == create["surfaceId"] for m in messages[1:])
    roots = [c for m in messages[1:] for c in m["updateComponents"]["components"] if c["id"] == "root"]
    assert {r["component"] for r in roots} == {"Answer"}
    assert roots[-1]["children"] == [c["id"] for c in a2ui_parts(events)]  # every part, in order
    chips = a2ui_parts(events)[0]
    assert chips["ward"] == "URO" and chips["as_of"] == "2026-09-27"  # the params are the properties
    assert kinds(events).index("header") < kinds(events).index("a2ui")


def test_clarify_and_in_short_become_catalog_components():
    async def go():
        events = [("header", {}), ("clarify", {"question": "Where?", "options": ["Home", "Hospital"]}), ("in_short", {"text": None}), ("done", {})]

        async def source():
            for e in events:
                yield e

        return [e async for e in a2ui.to_a2ui(source(), a2ui.AnswerSurface("s1"))]

    parts = a2ui_parts(asyncio.run(go()))
    assert parts == [
        {"question": "Where?", "options": ["Home", "Hospital"], "id": "p1", "component": "Clarify"},
        {"id": "p2", "component": "InShort"},  # no text: the app shows its placeholder
    ]


def test_no_widget_param_collides_with_the_a2ui_keys():
    for name, model in CATALOG.items():
        assert not {"id", "component", "children"} & set(model.model_fields), name


def test_without_a_key_the_route_answers_503_and_the_rest_of_the_api_works(monkeypatch):
    monkeypatch.setattr(settings, "anthropic_api_key", "")
    r = client.post("/v1/agent/screen", json={"message": "hello"})
    assert r.status_code == 503 and "no API key" in r.json()["detail"]
    assert client.get("/v1/alerts").status_code == 200
    assert client.get("/v1/organisms?ward=URO&infection_type=uti").status_code == 200


def test_an_empty_message_is_rejected():
    assert client.post("/v1/agent/screen", json={"message": ""}).status_code == 422


def test_a_ping_comment_is_sent_while_the_model_is_quiet(monkeypatch):
    monkeypatch.setattr(route, "HEARTBEAT_SECONDS", 0.05)
    slow = FakeClient(lambda _: [FakeTurn([use("render_widget", widget="OrganismMix", params={"ward": "URO"})], delay=0.3), FakeTurn(stop_reason="end_turn")])

    async def go():
        return [chunk async for chunk in route.event_stream(req(), slow)]

    chunks = asyncio.run(go())
    assert route.PING in chunks and chunks[-1].startswith("event: done")
    assert chunks.index(route.PING) > 0


def test_a_key_stored_with_a_trailing_newline_still_works():
    """Key Vault returned the key with a newline once; the SDK called that a connection error."""
    from app.config import Settings

    assert Settings(anthropic_api_key="sk-ant-abc\n").anthropic_api_key == "sk-ant-abc"
    assert Settings(anthropic_api_key="  sk-ant-abc \r\n").anthropic_api_key == "sk-ant-abc"


def test_a_connection_error_never_logs_the_key(caplog):
    """The SDK's header error carries the header value, which is the API key."""
    secret = "sk-ant-THIS-MUST-NOT-APPEAR"
    cause = RuntimeError(f"Illegal header value b'{secret}'")
    error = anthropic.APIConnectionError(request=httpx2.Request("POST", "http://x"))
    error.__cause__ = cause

    class Broken:
        async def turn(self, **kw):
            raise error
            yield  # pragma: no cover

    async def go():
        return [e async for e in loop.run(req(), Broken())]

    with caplog.at_level("INFO", logger="uvicorn.error"):
        events = asyncio.run(go())
    assert secret not in caplog.text and secret not in json.dumps(events)
    assert "RuntimeError" in caplog.text  # the type is logged, which is enough to find the cause


# ---- "In short" for the results pages---------------------------------------------------------

SUMMARY_Q = {"ward": "URO", "infection_type": "uti", "sex": "F", "age_band": "75+", "onset": "hospital"}


def line_client(*texts: str) -> FakeClient:
    """Writes each text in turn, one in_short call per turn."""
    return FakeClient(lambda _: [FakeTurn([use("in_short", f"s{i}", text=t)], stop_reason="tool_use") for i, t in enumerate(texts)])


def write_line(fake: FakeClient, kind=None, q=None):
    from app.agent import summary
    from app.models.data import CoverageQuery

    return asyncio.run(summary.write(kind or summary.COVERAGE, q or CoverageQuery(**SUMMARY_Q), fake))


def sent_results(fake: FakeClient) -> dict:
    return json.loads(fake.calls[0]["messages"][0]["content"])


def test_in_short_route_writes_a_checked_line(monkeypatch):
    from app.agent import summary

    summary._cache.clear()
    fake = line_client("E. coli leads here.")
    monkeypatch.setattr(summary, "make_summary_client", lambda: fake)
    r = client.get("/v1/agent/in-short", params=SUMMARY_Q)
    assert r.status_code == 200
    assert r.json() == {"text": "E. coli leads here.", "built_from": ["coverage", "organism mix", "alerts"]}
    cov = client.get("/v1/coverage", params=SUMMARY_Q).json()
    assert sent_results(fake)["coverage"] == cov  # the same numbers as the page's hero and table


def test_the_alert_line_is_built_from_the_alert_page_and_its_linked_wards():
    from app.agent import summary
    from app.models.alerts import AlertDetailQuery

    alert = next(a for a in client.get("/v1/alerts", params={"status": "active"}).json()["alerts"] if a["ward"])
    fake = line_client("Looks real; check the isolates.")
    out = write_line(fake, summary.ALERT, AlertDetailQuery(alert_id=alert["alert_id"]))
    assert out.text == "Looks real; check the isolates."
    sent = sent_results(fake)
    assert sent["alert_page"] == client.get("/v1/alerts/detail", params={"alert_id": alert["alert_id"]}).json()
    assert sent["linked_wards"]["ward"] == alert["ward"]
    assert out.built_from == ["alert detail", "sampling volume", "linked wards"]


def test_an_unknown_alert_gives_no_line_and_no_model_call():
    from app.agent import summary
    from app.models.alerts import AlertDetailQuery

    fake = line_client("Anything.")
    assert write_line(fake, summary.ALERT, AlertDetailQuery(alert_id="no-such-alert")).text is None
    assert fake.calls == []


def test_the_spreading_line_uses_the_pages_own_counts_for_its_ward():
    from app.agent import summary

    fake = line_client("Urology is above its usual level.")
    write_line(fake, summary.SPREADING, summary.SpreadingInShortQuery(phenotype="ESBL", ward="URO"))
    sent = sent_results(fake)
    series = client.get("/v1/spreading/series").json()
    row = next(r for r in series["rows"] if r["ward"] == "URO" and r["phenotype"] == "ESBL")
    assert sent["focus"]["last_4_weeks"] == sum(row["weekly"][-4:])  # the hero's count
    assert sent["focus"]["usual_4_weeks"] == round(row["normal_weekly"] * 4, 1)
    assert {r["phenotype"] for r in sent["wards"]} == {"ESBL"}
    assert sent["linked_wards"]["ward"] == "URO"


def test_without_a_ward_the_spreading_line_has_no_focus():
    from app.agent import summary

    fake = line_client("No ward is above its usual level for VRE.")
    write_line(fake, summary.SPREADING, summary.SpreadingInShortQuery(phenotype="VRE"))
    sent = sent_results(fake)
    assert sent["focus"] is None and sent["linked_wards"] is None


def test_in_short_with_an_invented_number_is_asked_again_once():
    fake = line_client("NIT covers 123% of these.", "NIT covers most of these.")
    assert write_line(fake).text == "NIT covers most of these."
    assert "123" in json.dumps(fake.calls[1]["messages"][-1])  # the model was told which number


def test_in_short_with_two_invented_numbers_is_dropped():
    assert write_line(line_client("NIT covers 123%.", "NIT covers 456%.")).text is None


def test_in_short_sees_only_the_in_short_tool_and_the_results():
    fake = line_client("E. coli leads.")
    write_line(fake)
    (call,) = fake.calls
    assert [t["name"] for t in call["tools"]] == ["in_short"]
    sent = json.loads(call["messages"][0]["content"])
    assert set(sent) == {"patient", "coverage", "organisms", "alerts", "names"}
    assert sent["names"]["drugs"]["NIT"] == "nitrofurantoin" and sent["names"]["wards"]["SURG"] == "Surgery"
    assert sent["coverage"]["recent"]["window"]["as_of"] == "2026-09-27"


def test_in_short_is_remembered_per_query():
    from app.agent import summary
    from app.models.data import CoverageQuery

    summary._cache.clear()
    fake = line_client("E. coli leads.")
    q = CoverageQuery(**SUMMARY_Q)
    first = asyncio.run(summary.in_short(summary.COVERAGE, q, fake))
    again = asyncio.run(summary.in_short(summary.COVERAGE, q, line_client("Something else.")))
    assert first.text == again.text == "E. coli leads."


def test_in_short_without_a_key_answers_503(monkeypatch):
    monkeypatch.setattr(settings, "anthropic_api_key", "")
    assert client.get("/v1/agent/in-short", params=SUMMARY_Q).status_code == 503
    assert client.get("/v1/agent/in-short/alert", params={"alert_id": "x"}).status_code == 503
    assert client.get("/v1/agent/in-short/spreading").status_code == 503


# ---- conversation history ----------------------------------------------------------------------


def test_history_goes_in_the_user_turn_not_the_cached_prefix():
    from app.agent.schema import HistoryTurn

    history = [
        HistoryTurn(role="user", text="My patient has an infection"),
        HistoryTurn(role="assistant", text="Asked: Which ward? Options: Surgery | Urology"),
    ]
    fake = FakeClient(lambda _: [FakeTurn(stop_reason="end_turn")])
    collect(req("Surgery", history=history), fake)
    sent = json.loads(fake.calls[0]["messages"][0]["content"])
    assert sent["history"] == [t.model_dump() for t in history]
    assert sent["message"] == "Surgery"
    from app.agent.prompt import SYSTEM_PROMPT

    assert fake.calls[0]["system"] == SYSTEM_PROMPT  # the cached prefix stays the same for every request


def test_without_history_the_user_turn_has_no_history_key():
    fake = FakeClient(lambda _: [FakeTurn(stop_reason="end_turn")])
    collect(req(), fake)
    assert "history" not in json.loads(fake.calls[0]["messages"][0]["content"])


def test_a_too_long_history_is_rejected():
    turns = [{"role": "user", "text": "x"}] * 25
    assert client.post("/v1/agent/screen", json={"message": "hi", "history": turns}).status_code == 422
