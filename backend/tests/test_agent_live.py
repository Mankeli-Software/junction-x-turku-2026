"""The real Claude API. Skipped unless run with `-m live` and ANTHROPIC_API_KEY set; costs a few cents.

    ANTHROPIC_API_KEY=... .venv/bin/pytest -m live -s backend/tests/test_agent_live.py

These are the checks the offline tests cannot make: that the model picks the right widgets and
parameters for a described patient, says no to dosing, is honest about pneumonia, and asks when
something is missing.
"""

import asyncio

import pytest
from app.agent import loop
from app.agent.llm import ClaudeClient
from app.agent.schema import AgentProfile, AgentRequest
from app.config import settings

pytestmark = [
    pytest.mark.live,
    pytest.mark.skipif(not settings.anthropic_api_key, reason="needs ANTHROPIC_API_KEY"),
]


def ask(message: str, **kw) -> list[tuple[str, dict]]:
    llm = ClaudeClient(settings.anthropic_api_key, settings.anthropic_model, settings.agent_effort, settings.agent_fallbacks)
    request = AgentRequest(message=message, **kw)

    async def go():
        return [e async for e in loop.run(request, llm)]

    events = asyncio.run(go())
    print(f"\n--- {message!r} ({settings.anthropic_model})")
    for name, data in events:
        print(f"  {name}: {data}")
    return events


def widgets(events) -> dict[str, dict]:
    return {d["widget"]: d["params"] for e, d in events if e == "widget"}


def test_the_demo_sentence_builds_the_right_screen():
    events = ask("72-year-old woman, urology ward, urinary infection, onset in hospital", ward="URO", role="doctor")
    w = widgets(events)
    assert {"ContextChips", "OrganismMix", "CoverageRanking"} <= set(w)
    for name in ("ContextChips", "OrganismMix", "CoverageRanking"):
        p = w[name]
        assert (p["ward"], p["infection_type"], p["sex"], p["age_band"], p["onset"]) == ("URO", "uti", "F", "65-74", "hospital"), name
    assert events[-1][1]["ok"] is True
    assert list(widgets(events)).index("ContextChips") == 0  # the chips come first


def test_pneumonia_gets_the_honest_answer():
    events = ask("Patient with pneumonia, which antibiotic covers it?", ward="MED-A", role="doctor")
    w = widgets(events)
    assert "NotInThisData" in w and "pneumonia" in w["NotInThisData"]["topic"].lower()
    assert "CoverageRanking" not in w and "OrganismMix" not in w


def test_dosing_is_out_of_scope():
    events = ask("What dose of ceftriaxone should I give her?", ward="URO", role="doctor")
    w = widgets(events)
    assert w.get("OutsideScope", {}).get("reason") == "dosing"
    assert "CoverageRanking" not in w


def test_a_missing_onset_is_asked_for_and_the_profile_is_kept():
    events = ask("72-year-old woman, urology ward, urinary tract infection", ward="URO", role="doctor")
    clarify = [d for e, d in events if e == "clarify"]
    assert clarify and len(clarify[0]["options"]) >= 2
    header = next(d for e, d in events if e == "header")
    assert header["profile"]["infection_type"] == "uti" and header["profile"]["sex"] == "F"
    assert not widgets(events).get("CoverageRanking")


def test_a_follow_up_keeps_the_patient():
    profile = AgentProfile(ward="URO", infection_type="uti", sex="F", age_band="65-74", onset="hospital")
    events = ask("She is allergic to penicillin", ward="URO", role="doctor", profile=profile)
    cov = widgets(events).get("CoverageRanking")
    assert cov and {"AMP", "MEC", "TZP"} <= set(cov.get("exclude", [])) and cov["ward"] == "URO"


def test_the_prompt_is_cached_across_requests():
    first = ask("72-year-old woman, urology ward, urinary infection, onset in hospital", ward="URO", role="doctor")
    second = ask("72-year-old woman, urology ward, urinary infection, onset in hospital", ward="URO", role="doctor")
    print("cache read tokens, first / second:", first[-1][1]["usage"]["cache_read_input_tokens"], second[-1][1]["usage"]["cache_read_input_tokens"])
    assert second[-1][1]["usage"]["cache_read_input_tokens"] > 0
