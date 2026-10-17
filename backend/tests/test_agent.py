"""The chat agent against a scripted fake client: no network, no key."""

import asyncio
import json
from datetime import date

import anthropic
import httpx2
import pytest
from app.agent import loop, route
from app.agent.llm import FakeClient, FakeTurn, ToolUse, demo_script
from app.agent.numbers import allowed_values, unsupported
from app.agent.schema import AgentProfile, AgentRequest
from app.agent.tools import DATA_TOOLS, UI_TOOLS, tool_definitions
from app.config import settings
from app.main import app
from app.registry import REGISTRY
from app.widgets.catalog import CATALOG
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


def test_the_route_streams_server_sent_events_with_the_right_headers(monkeypatch):
    monkeypatch.setattr(settings, "agent_fake", True)
    r = client.post("/v1/agent/screen", json={"message": "describe", "profile": PROFILE.model_dump()})
    assert r.status_code == 200 and r.headers["content-type"].startswith("text/event-stream")
    assert r.headers["cache-control"] == "no-cache" and r.headers["x-accel-buffering"] == "no"
    events = parse_sse(r.text)
    assert [d["widget"] for e, d in events if e == "widget"] == ["ContextChips", "OrganismMix", "CoverageRanking"]
    assert events[-1][0] == "done"


def test_without_a_key_the_route_answers_503_and_the_rest_of_the_api_works(monkeypatch):
    monkeypatch.setattr(settings, "agent_fake", False)
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
