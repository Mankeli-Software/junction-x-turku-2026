import logging

from fastapi import HTTPException

from app import dashboard_store
from app.models.dashboard import DashboardOut, DashboardPut, DashboardQuery, WidgetPlacement
from app.registry import register

log = logging.getLogger(__name__)


def _default(user_id: str) -> DashboardOut:
    return DashboardOut(
        user_id=user_id,
        role="doctor",
        layout=[
            WidgetPlacement(widget="ContextChips"),
            WidgetPlacement(widget="OrganismMix", params={"ward": "URO", "window": "28d"}),
            WidgetPlacement(widget="CoverageRanking", params={"ward": "URO", "window": "28d"}),
        ],
    )


@register("get_dashboard", "A user's saved layout and role.", "/dashboard", DashboardQuery, DashboardOut)
def get_dashboard(q: DashboardQuery) -> DashboardOut:
    try:
        saved = dashboard_store.store.get(q.user_id)
    except dashboard_store.StoreUnavailable:
        # A read must not break the screen: show the default layout and say why in the log.
        log.warning("dashboard read failed, serving the default layout", exc_info=True)
        saved = None
    return saved or _default(q.user_id)


@register("put_dashboard", "Save a user's layout.", "/dashboard", DashboardPut, DashboardOut, method="PUT")
def put_dashboard(q: DashboardPut) -> DashboardOut:
    out = DashboardOut(user_id=q.user_id, role=q.role, layout=q.layout)
    try:
        dashboard_store.store.put(out)
    except dashboard_store.StoreUnavailable as e:
        log.exception("dashboard save failed")
        raise HTTPException(status_code=503, detail="Could not save the dashboard, try again.") from e
    return out
