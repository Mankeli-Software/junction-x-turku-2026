from app.models.dashboard import DashboardOut, DashboardPut, DashboardQuery, WidgetPlacement
from app.registry import register

_SAVED: dict[str, DashboardOut] = {}  # in-memory stub; Postgres user_dashboards later


@register("get_dashboard", "A user's saved layout and role.", "/dashboard", DashboardQuery, DashboardOut)
def get_dashboard(q: DashboardQuery) -> DashboardOut:
    return _SAVED.get(q.user_id) or DashboardOut(
        user_id=q.user_id,
        role="doctor",
        layout=[
            WidgetPlacement(widget="ContextChips"),
            WidgetPlacement(widget="OrganismMix", params={"ward": "URO", "window": "28d"}),
            WidgetPlacement(widget="CoverageRanking", params={"ward": "URO", "window": "28d"}),
        ],
    )


@register("put_dashboard", "Save a user's layout.", "/dashboard", DashboardPut, DashboardOut, method="PUT")
def put_dashboard(q: DashboardPut) -> DashboardOut:
    out = DashboardOut(user_id=q.user_id, role=q.role, layout=q.layout)
    _SAVED[q.user_id] = out
    return out
