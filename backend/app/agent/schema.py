"""Request body and the SSE wire format of POST /v1/agent/screen.

The answer itself is an A2UI v0.9 surface (app/agent/a2ui.py) that the Flutter app renders with
genui from its own catalog; the other events are the chat's chrome around it and map onto the
app's AgentEvent types one to one:

  event: header    data: {"built_from": [...], "note": null, "profile": {...} | null}
  event: status    data: {"text": "..."}
  event: a2ui      data: {"version": "v0.9", "createSurface": {"surfaceId", "catalogId"}}
  event: a2ui      data: {"version": "v0.9", "updateComponents": {"surfaceId", "components": [...]}}
                   one per part: a catalog widget (loads its own numbers), InShort {text?} (the only
                   free text; no text = placeholder) or Clarify {question, options}
  event: error     data: {"code": "...", "message": "..."}
  event: done      data: {"ok": true, "usage": {...}}
  : ping                                                                   comment line every 15 s

Inside the server the loop yields widget / in_short / clarify events; route.py turns them into a2ui.
"""

import json
from datetime import date
from typing import Any, Literal

from pydantic import BaseModel, Field

from app.models.dashboard import Role, WidgetPlacement
from app.vocab import DEFAULT_AS_OF, AgeBand, InfectionType, Onset, Sex, Specimen, Ward


class AgentProfile(BaseModel):
    """The patient of the conversation so far, as the app holds it."""

    ward: Ward | None = None
    infection_type: InfectionType | None = None
    specimen: Specimen | None = None
    sex: Sex | None = None
    age_band: AgeBand | None = None
    onset: Onset | None = None


class HistoryTurn(BaseModel):
    """One earlier turn of the conversation: what the user asked, or what the agent showed or asked."""

    role: Literal["user", "assistant"]
    text: str = Field(max_length=1500)


class AgentRequest(BaseModel):
    message: str = Field(min_length=1, max_length=2000)
    as_of: date = DEFAULT_AS_OF
    role: Role = "doctor"
    ward: Ward | None = Field(None, description="the user's own ward")
    wards: list[Ward] = Field(default_factory=list, description="all wards the user looks after")
    profile: AgentProfile | None = None
    history: list[HistoryTurn] = Field(
        default_factory=list,
        max_length=24,
        description="earlier turns, oldest first, so a short reply is read as the answer to the last question",
    )


class WidgetAgentRequest(BaseModel):
    """POST /v1/agent/widget: what the user wants on their home page (app/agent/builder.py).

    Wire format, plain events (not A2UI: the app shows one proposal at a time in its own sheet):

      event: status    data: {"text": "..."}
      event: proposal  data: {"widget": "...", "params": {...}, "why": "..." | null}   params never carry as_of
      event: clarify   data: {"question": "...", "options": ["...", ...]}
      event: error     data: {"code": "...", "message": "..."}
      event: done      data: {"ok": true, "usage": {...}}
      : ping
    """

    message: str = Field(min_length=1, max_length=2000)
    as_of: date = DEFAULT_AS_OF
    role: Role = "doctor"
    ward: Ward | None = Field(None, description="the user's own ward")
    wards: list[Ward] = Field(default_factory=list, description="all wards the user looks after")
    layout: list[WidgetPlacement] = Field(default_factory=list, max_length=30, description="what is pinned now")
    history: list[HistoryTurn] = Field(
        default_factory=list,
        max_length=24,
        description="earlier turns, oldest first: the user's requests and what was proposed or asked",
    )


def sse(event: str, data: dict[str, Any]) -> str:
    """One server-sent event."""
    return f"event: {event}\ndata: {json.dumps(data, ensure_ascii=False, separators=(',', ':'))}\n\n"


PING = ": ping\n\n"
