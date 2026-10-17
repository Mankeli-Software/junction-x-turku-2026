"""Request body and the SSE wire format of POST /v1/agent/screen.

The events mirror the Flutter app's AgentEvent types one to one (header, status, part, actions,
unavailable), so the client maps them without logic:

  event: header    data: {"built_from": [...], "note": null, "profile": {...} | null}
  event: status    data: {"text": "..."}
  event: widget    data: {"widget": "CoverageRanking", "params": {...}}   catalog widget, loads its own numbers
  event: in_short  data: {"text": "..." | null}                            the only free text; null = placeholder
  event: clarify   data: {"question": "...", "options": ["...", ...]}
  event: error     data: {"code": "...", "message": "..."}
  event: done      data: {"usage": {...}}
  : ping                                                                   comment line every 15 s
"""

import json
from datetime import date
from typing import Any

from pydantic import BaseModel, Field

from app.models.dashboard import Role
from app.vocab import DEFAULT_AS_OF, AgeBand, InfectionType, Onset, Sex, Specimen, Ward


class AgentProfile(BaseModel):
    """The patient of the conversation so far, as the app holds it."""

    ward: Ward | None = None
    infection_type: InfectionType | None = None
    specimen: Specimen | None = None
    sex: Sex | None = None
    age_band: AgeBand | None = None
    onset: Onset | None = None


class AgentRequest(BaseModel):
    message: str = Field(min_length=1, max_length=2000)
    as_of: date = DEFAULT_AS_OF
    role: Role = "doctor"
    ward: Ward | None = Field(None, description="the user's own ward")
    wards: list[Ward] = Field(default_factory=list, description="all wards the user looks after")
    profile: AgentProfile | None = None


def sse(event: str, data: dict[str, Any]) -> str:
    """One server-sent event."""
    return f"event: {event}\ndata: {json.dumps(data, ensure_ascii=False, separators=(',', ':'))}\n\n"


PING = ": ping\n\n"
