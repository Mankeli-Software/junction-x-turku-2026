"""The widget builder (POST /v1/agent/widget) and the role defaults of the home dashboard."""

import asyncio
import json

import pytest
from app.agent import builder, route
from app.agent.llm import ToolUse
from app.agent.schema import WidgetAgentRequest
from app.config import settings
from app.functions.dashboard import default_layout
from app.main import app
from app.models.dashboard import WidgetPlacement
from app.widgets.catalog import CATALOG, PINNABLE
from fake_llm import FakeClient, FakeTurn
from fastapi.testclient import TestClient

client = TestClient(app)


def req(message="MRSA on my ward this year", **kw) -> WidgetAgentRequest:
    return WidgetAgentRequest(message=message, ward="URO", **kw)


def play(turns, request: WidgetAgentRequest | None = None) -> tuple[list[tuple[str, dict]], FakeClient]:
    fake = FakeClient(lambda _: list(turns))

    async def go():
        return [e async for e in builder.run(request or req(), fake)]

    return asyncio.run(go()), fake


def propose(id_="p1", why="Shows the trend on your ward.", **inp) -> ToolUse:
    return ToolUse(id_, "propose_widget", {"why": why, **inp})


def results(fake: FakeClient, call: int) -> list[dict]:
    """The tool results sent back at the start of model call `call`."""
    return fake.calls[call]["messages"][-1]["content"]


TREND = {"organism": "Escherichia coli", "drug": "TMP", "ward": "URO"}


# ---- proposals ------------------------------------------------------------------------------


def test_a_proposal_is_a_pinned_placement_without_as_of_or_defaults():
    events, fake = play([FakeTurn([propose(widget="ResistanceTrend", params={**TREND, "as_of": "2020-01-01", "window": "28d"})])])
    (p,) = [d for e, d in events if e == "proposal"]
    assert p == {"widget": "ResistanceTrend", "params": TREND, "why": "Shows the trend on your ward."}
    assert events[-1] == ("done", {"ok": True, "usage": events[-1][1]["usage"]})
    assert len(fake.calls) == 1  # the run stops after the proposal and waits for the user


def test_a_widget_already_on_the_home_page_is_refused_and_the_model_picks_another():
    layout = [WidgetPlacement(widget="CoverageRanking", params={"ward": "URO", "infection_type": "uti"})]
    events, fake = play(
        [
            FakeTurn([propose(widget="CoverageRanking", params={"ward": "URO", "infection_type": "uti", "window": "28d"})]),
            FakeTurn([propose("p2", widget="CoverageRanking", params={"ward": "URO", "infection_type": "uti", "window": "365d"})]),
        ],
        req(layout=layout),
    )
    assert [d["params"]["window"] for e, d in events if e == "proposal"] == ["365d"]
    (first,) = results(fake, 1)
    assert first["is_error"] and "already on the user's home page" in first["content"]


def test_only_pinnable_widgets_can_be_proposed():
    events, fake = play([FakeTurn([propose(widget="ContextChips", params={"ward": "URO"})]), FakeTurn([propose("p2", widget="OrganismMix", params={"ward": "URO"})])])
    assert [d["widget"] for e, d in events if e == "proposal"] == ["OrganismMix"]
    assert "cannot be pinned" in results(fake, 1)[0]["content"]


def test_bad_params_come_back_as_an_error_the_model_can_fix():
    events, fake = play([FakeTurn([propose(widget="ResistanceTrend", params={"ward": "URO"})]), FakeTurn([propose("p2", widget="ResistanceTrend", params=TREND)])])
    assert [d["widget"] for e, d in events if e == "proposal"] == ["ResistanceTrend"]
    assert "bad params for ResistanceTrend" in results(fake, 1)[0]["content"]


def test_one_proposal_per_turn():
    events, _ = play([FakeTurn([propose(widget="OrganismMix", params={"ward": "URO"}), propose("p2", widget="SpreadingCounts", params={})])])
    assert [d["widget"] for e, d in events if e == "proposal"] == ["OrganismMix"]


def test_ask_user_ends_the_run():
    events, fake = play([FakeTurn([ToolUse("a", "ask_user", {"question": "Which one?", "options": ["Trend over time", "Last 4 weeks vs 12 months"]})])])
    assert ("clarify", {"question": "Which one?", "options": ["Trend over time", "Last 4 weeks vs 12 months"]}) in events
    assert "proposal" not in [e for e, _ in events] and len(fake.calls) == 1


def test_a_why_with_an_invented_number_is_rewritten_once_then_dropped():
    bad = "Resistance rose to 57 percent."
    events, fake = play(
        [
            FakeTurn([propose(widget="OrganismMix", params={"ward": "URO"}, why=bad)]),
            FakeTurn([propose("p2", widget="OrganismMix", params={"ward": "URO"}, why=bad)]),
        ]
    )
    (p,) = [d for e, d in events if e == "proposal"]
    assert p["why"] is None and p["widget"] == "OrganismMix"
    assert "57" in results(fake, 1)[0]["content"]


def test_a_turn_without_a_proposal_is_an_error():
    events, _ = play([FakeTurn(stop_reason="end_turn")])
    assert ("error", {"code": "no_proposal", "message": events[0][1]["message"]}) == events[0]
    assert events[-1][1]["ok"] is False


def test_data_tools_run_and_their_numbers_may_be_quoted():
    def pick(messages):
        alerts = json.loads(messages[-1]["content"][0]["content"])["alerts"]
        sentinel = next(a for a in alerts if a["type"] == "sentinel")
        return FakeTurn([propose(widget="AlertCard", params={"alert_id": sentinel["alert_id"]}, why=f"The {sentinel['ward']} alert from {sentinel['first_seen']}.")])

    events, _ = play([FakeTurn([ToolUse("d", "get_alerts", {"status": "active"})]), pick])
    assert ("status", {"text": "Checking alerts…"}) in events
    (p,) = [d for e, d in events if e == "proposal"]
    assert p["params"]["alert_id"].startswith("sentinel-") and p["why"]


def test_the_history_and_layout_reach_the_model():
    layout = [WidgetPlacement(widget="SpreadingCounts", params={})]
    _, fake = play([FakeTurn([propose(widget="OrganismMix", params={})])], req("something else", layout=layout, history=[{"role": "assistant", "text": "Proposed ResistanceTrend {}: why"}]))
    ctx = json.loads(fake.calls[0]["messages"][0]["content"])
    assert ctx["layout"] == [{"widget": "SpreadingCounts", "params": {}}] and ctx["history"][0]["role"] == "assistant"
    assert "as_of" in ctx and ctx["ward"] == "URO"


def test_the_tools_offer_only_pinnable_widgets():
    tools = {t["name"]: t for t in builder.builder_tools()}
    assert tools["propose_widget"]["input_schema"]["properties"]["widget"]["enum"] == list(PINNABLE)
    assert "render_widget" not in tools and "in_short" not in tools
    assert "- ContextChips" not in builder.BUILDER_PROMPT and "- ResistanceTrend" in builder.BUILDER_PROMPT


# ---- the route ------------------------------------------------------------------------------


def test_the_route_streams_the_proposal(monkeypatch):
    fake = FakeClient(lambda _: [FakeTurn([propose(widget="SpreadingCounts", params={})])])
    monkeypatch.setattr(route, "make_client", lambda: fake)
    r = client.post("/v1/agent/widget", json={"message": "what is spreading", "layout": [{"widget": "AlertBanner", "params": {}}]})
    assert r.status_code == 200 and r.headers["content-type"].startswith("text/event-stream")
    assert "event: proposal\ndata: " + json.dumps({"widget": "SpreadingCounts", "params": {}, "why": "Shows the trend on your ward."}, separators=(",", ":")) in r.text
    assert r.text.rstrip().split("\n")[-2] == "event: done"


def test_without_a_key_the_route_answers_503(monkeypatch):
    monkeypatch.setattr(settings, "anthropic_api_key", "")
    r = client.post("/v1/agent/widget", json={"message": "hello"})
    assert r.status_code == 503


# ---- default layouts and reset --------------------------------------------------------------


@pytest.mark.parametrize("role", ["doctor", "hygiene", "care_worker", "lab", "researcher", None])
@pytest.mark.parametrize("ward", ["URO", None])
def test_every_default_placement_is_a_valid_pinnable_widget(role, ward):
    layout = default_layout(role, ward)
    assert layout
    for p in layout:
        assert p.widget in PINNABLE and "as_of" not in p.params
        CATALOG[p.widget].model_validate(p.params)


def test_the_doctor_default_links_to_every_page():
    layout = default_layout("doctor", "ED")
    assert [p.widget for p in layout] == ["CoverageRanking", "AlertBanner", "ResistanceTrend", "SpreadingCounts"]
    assert layout[0].params == {"ward": "ED", "infection_type": "uti"}
    assert layout[2].params == {"organism": "Escherichia coli", "drug": "TMP", "specimen": "urine", "ward": "ED"}
    assert "ward" not in default_layout("doctor", None)[0].params


def test_get_without_a_saved_layout_serves_the_role_default():
    d = client.get("/v1/dashboard?user_id=new&role=lab&ward=URO").json()
    assert d["role"] == "lab" and [w["widget"] for w in d["layout"]] == ["AlertBanner", "SamplingVolume", "ResistanceTrend"]
    assert client.get("/v1/dashboard?user_id=new2").json()["role"] == "doctor"


def test_delete_forgets_the_saved_layout_and_returns_the_default():
    body = {"user_id": "u9", "role": "doctor", "layout": [{"widget": "SpreadingCounts", "params": {}}]}
    assert client.put("/v1/dashboard", json=body).status_code == 200
    assert len(client.get("/v1/dashboard?user_id=u9&role=doctor").json()["layout"]) == 1
    r = client.delete("/v1/dashboard?user_id=u9&role=doctor&ward=URO")
    assert r.status_code == 200 and r.json()["layout"][0]["params"]["ward"] == "URO"
    assert client.get("/v1/dashboard?user_id=u9&role=doctor&ward=URO").json() == r.json()
