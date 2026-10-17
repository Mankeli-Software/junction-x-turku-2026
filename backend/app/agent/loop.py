"""The agent loop: one request in, a stream of (event, data) pairs out.

A manual loop, not the SDK tool runner, because each step has to become a server-sent event and be
validated first. Claude's tool calls are handled in three ways:
- render_widget / in_short / ask_user act on the screen the moment their input is complete, so the
  chips can reach the browser before the model has finished its turn;
- data tools run together after the turn, and all their results go back in one message;
- every tool call is answered, so the history stays valid.
"""

import asyncio
import json
import logging
import time
import uuid
from collections.abc import AsyncIterator
from typing import Any

import anthropic

from app.agent.llm import LLMClient, ToolUse, TurnEnd
from app.agent.numbers import allowed_values, unsupported
from app.agent.prompt import SYSTEM_PROMPT
from app.agent.schema import AgentRequest
from app.agent.tools import (
    DATA_TOOLS,
    ToolError,
    result_text,
    run_data_tool,
    tool_definitions,
    validate_ask,
    validate_text,
    validate_widget,
)

log = logging.getLogger("uvicorn.error")

MAX_ITERATIONS = 8
MAX_JSON_RETRIES = 2  # a turn whose tool input could not be parsed at all is asked again
MAX_REWRITES = 1  # a summary with a number nobody supplied may be rewritten once, then it is dropped
PROFILE_FIELDS = ("ward", "infection_type", "specimen", "sex", "age_band", "onset")
LABELS = {
    "get_coverage": "coverage",
    "get_organisms": "organism mix",
    "get_susceptibility": "susceptibility",
    "get_alerts": "alerts",
    "get_alert_detail": "alert detail",
    "get_spreading": "spreading",
    "get_volume": "sampling volume",
    "get_ward_links": "linked wards",
}
STATUS = {
    "get_coverage": "Checking antibiotic coverage…",
    "get_organisms": "Checking the likely organisms…",
    "get_susceptibility": "Checking susceptibility…",
    "get_alerts": "Checking alerts…",
    "get_alert_detail": "Reading the alert…",
    "get_spreading": "Checking resistant bacteria on every ward…",
    "get_volume": "Checking how many cultures were sent…",
    "get_ward_links": "Checking linked wards…",
}
REFUSAL_MESSAGE = "I can't help with that here."

Event = tuple[str, dict[str, Any]]


def _blocks(content: list[Any], kind: str) -> list[Any]:
    return [b for b in content if (b.get("type") if isinstance(b, dict) else getattr(b, "type", None)) == kind]


def _field(block: Any, key: str) -> Any:
    return block.get(key) if isinstance(block, dict) else getattr(block, key, None)


def user_turn(req: AgentRequest) -> str:
    """Everything that changes per request. It goes in the user turn, never in the cached prefix."""
    return json.dumps(
        {
            "as_of": req.as_of.isoformat(),
            "role": req.role,
            "ward": req.ward,
            "wards": req.wards,
            "profile": req.profile.model_dump(exclude_none=True) if req.profile else None,
            **({"history": [t.model_dump() for t in req.history]} if req.history else {}),
            "message": req.message,
        },
        ensure_ascii=False,
    )


def _profile_from(params: dict[str, Any]) -> dict[str, Any]:
    return {k: params[k] for k in PROFILE_FIELDS if params.get(k)}


async def run(req: AgentRequest, llm: LLMClient) -> AsyncIterator[Event]:
    request_id = uuid.uuid4().hex[:8]
    started = time.perf_counter()
    first_widget_s: float | None = None
    context = user_turn(req)
    messages: list[dict[str, Any]] = [{"role": "user", "content": context}]
    tools = tool_definitions()
    sources: list[Any] = [context]  # what the summary may quote: this request's context and tool results
    built_from: list[str] = []
    profile: dict[str, Any] = req.profile.model_dump(exclude_none=True) if req.profile else {}
    placed: set[str] = set()
    summary_done, rewrites, json_retries, iteration = False, 0, 0, 0
    usage = {"input_tokens": 0, "output_tokens": 0, "cache_read_input_tokens": 0, "cache_creation_input_tokens": 0}
    stop_reason, model, ok = "", "", True

    def header() -> Event:
        return "header", {"built_from": list(built_from), "note": None, "profile": profile or None}

    try:
        while iteration < MAX_ITERATIONS:
            ui_results: dict[str, tuple[str, bool]] = {}
            data_uses: list[ToolUse] = []
            asked = False
            end: TurnEnd | None = None
            try:
                async for ev in llm.turn(system=SYSTEM_PROMPT, tools=tools, messages=messages):
                    if isinstance(ev, TurnEnd):
                        end = ev
                        continue
                    if ev.name == "render_widget":
                        try:
                            widget, params = validate_widget(ev.input, req.as_of)
                            key = json.dumps([widget, params], sort_keys=True)
                            if key in placed:
                                ui_results[ev.id] = ("Already on the screen.", False)
                            else:
                                placed.add(key)
                                if first_widget_s is None:
                                    first_widget_s = time.perf_counter() - started
                                if widget == "ContextChips":
                                    profile = _profile_from(params) or profile
                                    yield header()
                                yield "widget", {"widget": widget, "params": params}
                                ui_results[ev.id] = ("Placed.", False)
                        except ToolError as e:
                            ui_results[ev.id] = (str(e), True)
                    elif ev.name == "in_short":
                        try:
                            text = validate_text(ev.input)
                            if summary_done:
                                ui_results[ev.id] = ("The summary is already placed.", False)
                                continue
                            bad = unsupported(text, allowed_values(sources))
                            if not bad:
                                summary_done = True
                                yield "in_short", {"text": text}
                                ui_results[ev.id] = ("Placed.", False)
                            elif rewrites >= MAX_REWRITES:
                                summary_done = True
                                yield "in_short", {"text": None}  # the app shows its placeholder
                                ui_results[ev.id] = ("Dropped; the screen shows a placeholder. Do not call in_short again.", False)
                            else:
                                rewrites += 1
                                ui_results[ev.id] = (
                                    (
                                        f"These numbers are not in any tool result: {', '.join(bad)}. Write the line again "
                                        "without them, or call a data tool first and quote its numbers."
                                    ),
                                    True,
                                )
                        except ToolError as e:
                            ui_results[ev.id] = (str(e), True)
                    elif ev.name == "ask_user":
                        try:
                            question, options, understood = validate_ask(ev.input)
                            if understood:
                                profile = {**profile, **understood}
                            yield header()
                            yield "clarify", {"question": question, "options": options}
                            asked = True
                            ui_results[ev.id] = ("Asked. Stop and wait for the user's answer.", False)
                        except ToolError as e:
                            ui_results[ev.id] = (str(e), True)
                    elif ev.name in DATA_TOOLS:
                        data_uses.append(ev)
                    else:
                        ui_results[ev.id] = (f"Unknown tool {ev.name!r}.", True)
            except ValueError:
                # Tool input the SDK could not parse at all: nothing was answered, so ask the turn again.
                json_retries += 1
                if json_retries > MAX_JSON_RETRIES:
                    raise
                continue
            json_retries = 0
            iteration += 1
            if end is None:
                break
            for k in usage:
                usage[k] += end.usage.get(k, 0)
            stop_reason, model = end.stop_reason, end.model or model

            if end.stop_reason == "refusal":
                ok = False
                yield "error", {"code": "refusal", "message": REFUSAL_MESSAGE}
                break
            if end.stop_reason == "max_tokens":
                ok = False
                yield "error", {"code": "too_long", "message": "The answer got too long. Try a shorter question."}
                break
            if end.stop_reason == "pause_turn":
                messages.append({"role": "assistant", "content": end.content})
                continue
            if end.stop_reason != "tool_use" or asked or (summary_done and not data_uses):
                break  # a finished screen needs no extra round trip just to hear the model say it is done

            # Data tools run together; every tool call gets a result, in the order the model made them.
            if data_uses:
                for name in dict.fromkeys(u.name for u in data_uses):
                    yield "status", {"text": STATUS[name]}
            outcomes = await asyncio.gather(*(run_data_tool(u.name, u.input, req.as_of) for u in data_uses), return_exceptions=True)
            data_results: dict[str, tuple[str, bool]] = {}
            for use, out in zip(data_uses, outcomes, strict=True):
                if isinstance(out, ToolError):
                    data_results[use.id] = (str(out), True)
                elif isinstance(out, BaseException):
                    raise out
                else:
                    sources.append(out)
                    if LABELS[use.name] not in built_from:
                        built_from.append(LABELS[use.name])
                    data_results[use.id] = (result_text(out), False)
            results = []
            for block in _blocks(end.content, "tool_use"):
                bid = _field(block, "id")
                text, is_error = ui_results.get(bid) or data_results.get(bid) or ("Not run.", True)
                results.append({"type": "tool_result", "tool_use_id": bid, "content": text, **({"is_error": True} if is_error else {})})
            messages.append({"role": "assistant", "content": end.content})
            messages.append({"role": "user", "content": results})
        else:
            ok = False
            yield "error", {"code": "too_many_steps", "message": "That took too many steps. Try a simpler question."}
    except anthropic.RateLimitError:
        ok = False
        yield "error", {"code": "rate_limited", "message": "The AI is busy right now. Try again in a moment."}
    except anthropic.AuthenticationError:
        ok = False
        log.error("agent %s: the Anthropic key was rejected", request_id)
        yield "error", {"code": "unavailable", "message": "AI answers are paused right now."}
    except anthropic.APITimeoutError:
        ok = False
        yield "error", {"code": "timeout", "message": "The AI took too long to answer."}
    except anthropic.APIConnectionError as e:
        ok = False
        # Only the type of the cause: the text of a header error contains the header, which is the API key.
        log.error("agent %s: connection error (cause: %s)", request_id, type(e.__cause__).__name__)
        yield "error", {"code": "unreachable", "message": "Could not reach the AI service."}
    except anthropic.APIStatusError as e:
        ok = False
        log.error("agent %s: API status %s", request_id, e.status_code)
        yield "error", {"code": "upstream", "message": "The AI service had a problem."}
    except Exception:
        ok = False
        log.exception("agent %s failed", request_id)
        yield "error", {"code": "internal", "message": "Something went wrong building the answer."}

    yield header()
    yield "done", {"ok": ok, "usage": usage}
    log.info(
        "agent %s: model=%s ok=%s iterations=%d stop=%s first_widget_s=%s in=%d out=%d cache_read=%d cache_write=%d total_s=%.1f",
        request_id, model or "-", ok, iteration, stop_reason or "-",
        f"{first_widget_s:.1f}" if first_widget_s is not None else "-",
        usage["input_tokens"], usage["output_tokens"], usage["cache_read_input_tokens"], usage["cache_creation_input_tokens"],
        time.perf_counter() - started,
    )
