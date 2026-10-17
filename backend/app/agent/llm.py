"""The model behind the agent: a thin wrapper around the Anthropic SDK, and a scripted fake.

The loop talks only to LLMClient, so tests and the offline demo use FakeClient and never touch the
network. One turn is one streamed request: it yields each tool call as soon as its input is
complete (so a widget can reach the browser before the turn ends), then the end of the turn.
"""

import logging
from collections.abc import AsyncIterator, Callable
from dataclasses import dataclass, field
from typing import Any, Protocol

import anthropic

from app.config import settings

log = logging.getLogger("uvicorn.error")

FALLBACK_BETA = "server-side-fallback-2026-07-01"


@dataclass
class ToolUse:
    id: str
    name: str
    input: Any


@dataclass
class TurnEnd:
    stop_reason: str
    content: list[Any]  # the assistant blocks, passed back unchanged (thinking blocks included)
    usage: dict[str, int] = field(default_factory=dict)
    model: str = ""


class LLMClient(Protocol):
    def turn(self, *, system: str, tools: list[dict[str, Any]], messages: list[dict[str, Any]]) -> AsyncIterator[ToolUse | TurnEnd]: ...


def _usage(u: Any) -> dict[str, int]:
    return {
        k: int(getattr(u, k, 0) or 0)
        for k in ("input_tokens", "output_tokens", "cache_read_input_tokens", "cache_creation_input_tokens")
    }


class ClaudeClient:
    """Streams one request to the Claude API.

    Thinking stays at the model default (always on for these models: `disabled` and `budget_tokens`
    return a 400). No temperature, top_p, top_k, prefill or forced tool_choice: they are rejected.
    """

    def __init__(self, api_key: str, model: str, effort: str, fallbacks: bool = False):
        self.model, self.effort, self.fallbacks = model, effort, fallbacks
        self.client = anthropic.AsyncAnthropic(api_key=api_key, timeout=60.0, max_retries=2)

    def _stream(self, system: str, tools: list[dict[str, Any]], messages: list[dict[str, Any]]):
        params: dict[str, Any] = {
            "model": self.model,
            "max_tokens": 16000,
            "system": system,
            "tools": tools,
            "messages": messages,
            "output_config": {"effort": self.effort},
            "cache_control": {"type": "ephemeral"},  # the tools and system prompt are the stable prefix
        }
        if self.fallbacks:
            return self.client.beta.messages.stream(**params, betas=[FALLBACK_BETA], fallbacks="default")
        return self.client.messages.stream(**params)

    async def turn(self, *, system: str, tools: list[dict[str, Any]], messages: list[dict[str, Any]]) -> AsyncIterator[ToolUse | TurnEnd]:
        async with self._stream(system, tools, messages) as stream:
            async for event in stream:
                if event.type == "content_block_stop" and getattr(event.content_block, "type", None) == "tool_use":
                    block = event.content_block
                    yield ToolUse(block.id, block.name, block.input)
            final = await stream.get_final_message()
        yield TurnEnd(final.stop_reason or "end_turn", list(final.content), _usage(final.usage), final.model)


def make_client() -> LLMClient | None:
    """The configured client, or None when there is no key (the route then answers 503)."""
    if settings.agent_fake:
        return FakeClient(demo_script)
    if not settings.anthropic_api_key:
        return None
    return ClaudeClient(settings.anthropic_api_key, settings.anthropic_model, settings.agent_effort, settings.agent_fallbacks)


# ---- scripted fake -----------------------------------------------------------------------------


@dataclass
class FakeTurn:
    tool_uses: list[ToolUse] = field(default_factory=list)
    stop_reason: str = "tool_use"
    delay: float = 0.0  # seconds before the turn ends, to exercise the heartbeat


class FakeClient:
    """Plays a script of turns. `script` gets the first user message and returns the turns.

    Later turns may be callables taking the messages so far, so a script can react to tool results.
    """

    def __init__(self, script: Callable[[str], list[Any]]):
        self.script = script
        self._turns: list[Any] | None = None
        self.calls: list[dict[str, Any]] = []

    async def turn(self, *, system: str, tools: list[dict[str, Any]], messages: list[dict[str, Any]]) -> AsyncIterator[ToolUse | TurnEnd]:
        import asyncio

        self.calls.append({"system": system, "tools": tools, "messages": list(messages)})
        if self._turns is None:
            self._turns = list(self.script(messages[0]["content"]))
        nxt = self._turns.pop(0) if self._turns else FakeTurn(stop_reason="end_turn")
        turn = nxt(messages) if callable(nxt) else nxt
        for use in turn.tool_uses:
            yield ToolUse(use.id, use.name, use.input)
        if turn.delay:
            await asyncio.sleep(turn.delay)
        content = [{"type": "tool_use", "id": u.id, "name": u.name, "input": u.input} for u in turn.tool_uses]
        yield TurnEnd(turn.stop_reason, content, {"input_tokens": 0, "output_tokens": 0}, "fake")


def demo_script(first_message: str) -> list[Any]:
    """The fixed doctor screen: chips, organisms, coverage and one line, for the profile in the request."""
    import json

    ctx = json.loads(first_message)
    p = ctx.get("profile") or {"ward": "URO", "infection_type": "uti", "sex": "F", "age_band": "75+", "onset": "hospital"}
    p = {"ward": ctx.get("ward"), **p}
    p = {k: v for k, v in p.items() if v}

    def widgets(_messages: list[dict[str, Any]]) -> FakeTurn:
        uses = [ToolUse(f"w{i}", "render_widget", {"widget": w, "params": p}) for i, w in enumerate(["ContextChips", "OrganismMix", "CoverageRanking"])]
        uses.append(ToolUse("s", "in_short", {"text": "Likely organisms and local susceptibility coverage for this profile, from this hospital's data."}))
        return FakeTurn(uses)

    return [widgets, FakeTurn(stop_reason="end_turn")]
