from typing import Any, Literal

from pydantic import BaseModel, Field

Role = Literal["doctor", "hygiene", "care_worker", "lab", "researcher"]


class DashboardQuery(BaseModel):
    user_id: str = "demo"


class WidgetPlacement(BaseModel):
    widget: str = Field(description="name from the widget catalog")
    params: dict[str, Any] = Field(default_factory=dict)


class DashboardOut(BaseModel):
    user_id: str
    role: Role
    layout: list[WidgetPlacement]


class DashboardPut(DashboardQuery):
    role: Role
    layout: list[WidgetPlacement]
