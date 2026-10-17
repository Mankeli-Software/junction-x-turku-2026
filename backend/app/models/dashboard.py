import json
from typing import Any, Literal

from pydantic import BaseModel, Field, field_validator

Role = Literal["doctor", "hygiene", "care_worker", "lab", "researcher"]

# A saved layout is a row in Postgres that anyone with the app's origin can write: keep it small.
MAX_PINS = 50
MAX_LAYOUT_CHARS = 20_000


class DashboardQuery(BaseModel):
    user_id: str = Field("demo", min_length=1, max_length=64)


class WidgetPlacement(BaseModel):
    widget: str = Field(description="name from the widget catalog")
    params: dict[str, Any] = Field(default_factory=dict)


class DashboardOut(BaseModel):
    user_id: str
    role: Role
    layout: list[WidgetPlacement]


class DashboardPut(DashboardQuery):
    role: Role
    layout: list[WidgetPlacement] = Field(max_length=MAX_PINS)

    @field_validator("layout")
    @classmethod
    def _small(cls, v: list[WidgetPlacement]) -> list[WidgetPlacement]:
        if len(json.dumps([w.model_dump() for w in v], default=str)) > MAX_LAYOUT_CHARS:
            raise ValueError(f"the layout is larger than {MAX_LAYOUT_CHARS} characters")
        return v
