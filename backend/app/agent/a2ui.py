"""The agent's screen as A2UI v0.9 messages (https://a2ui.org), for the Flutter app's genui renderer.

The loop yields plain events (widget, in_short, clarify); this module turns them into one A2UI
surface per answer, so the app renders it with genui's `Surface` from its own catalog:

  createSurface     {"surfaceId": ..., "catalogId": CATALOG_ID}           once, before the first part
  updateComponents  {"surfaceId": ..., "components": [part, root]}        once per part

Every part is a component of our catalog (`backend/app/widgets/catalog.py` plus InShort and
Clarify) with its parameters as properties; `root` is an `Answer` whose children list the parts in
the order they arrived. header, status, error and done stay plain events: they are the chat's own
chrome around the surface, not part of it.
"""

import uuid
from collections.abc import AsyncIterator
from typing import Any

VERSION = "v0.9"
CATALOG_ID = "https://amright.app/a2ui/v0_9/catalog.json"
ROOT_ID = "root"
ROOT = "Answer"
IN_SHORT = "InShort"
CLARIFY = "Clarify"

Event = tuple[str, dict[str, Any]]


class AnswerSurface:
    """Builds the A2UI messages of one answer, part by part."""

    def __init__(self, surface_id: str | None = None) -> None:
        self.surface_id = surface_id or f"answer-{uuid.uuid4().hex[:12]}"
        self.children: list[str] = []

    def create(self) -> dict[str, Any]:
        return {"version": VERSION, "createSurface": {"surfaceId": self.surface_id, "catalogId": CATALOG_ID}}

    def add(self, component: str, props: dict[str, Any]) -> dict[str, Any]:
        """Appends one part; the root is sent again with the new list of children."""
        cid = f"p{len(self.children) + 1}"
        self.children.append(cid)
        return {
            "version": VERSION,
            "updateComponents": {
                "surfaceId": self.surface_id,
                "components": [
                    {**props, "id": cid, "component": component},
                    {"id": ROOT_ID, "component": ROOT, "children": list(self.children)},
                ],
            },
        }


def part_of(event: str, data: dict[str, Any]) -> tuple[str, dict[str, Any]] | None:
    """(component, properties) for an event that puts something on the screen, else None."""
    if event == "widget":
        return data["widget"], dict(data["params"])
    if event == "in_short":
        return IN_SHORT, {"text": data["text"]} if data.get("text") else {}
    if event == "clarify":
        return CLARIFY, {"question": data["question"], "options": list(data["options"])}
    return None


async def to_a2ui(events: AsyncIterator[Event], surface: AnswerSurface | None = None) -> AsyncIterator[Event]:
    """Passes the chrome events through and turns the parts into `a2ui` events."""
    surface = surface or AnswerSurface()
    created = False
    async for event, data in events:
        part = part_of(event, data)
        if part is None:
            yield event, data
            continue
        if not created:
            created = True
            yield "a2ui", surface.create()
        yield "a2ui", surface.add(*part)
