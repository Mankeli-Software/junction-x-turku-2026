"""A scripted LLMClient for the offline agent tests: no network, no key."""

import asyncio
import json
from collections.abc import AsyncIterator, Callable
from dataclasses import dataclass, field
from typing import Any

from app.agent.llm import ToolUse, TurnEnd


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
    ctx = json.loads(first_message)
    p = ctx.get("profile") or {"ward": "URO", "infection_type": "uti", "sex": "F", "age_band": "75+", "onset": "hospital"}
    p = {"ward": ctx.get("ward"), **p}
    p = {k: v for k, v in p.items() if v}

    def widgets(_messages: list[dict[str, Any]]) -> FakeTurn:
        uses = [ToolUse(f"w{i}", "render_widget", {"widget": w, "params": p}) for i, w in enumerate(["ContextChips", "OrganismMix", "CoverageRanking"])]
        uses.append(ToolUse("s", "in_short", {"text": "Likely organisms and local susceptibility coverage for this profile, from this hospital's data."}))
        return FakeTurn(uses)

    return [widgets, FakeTurn(stop_reason="end_turn")]
