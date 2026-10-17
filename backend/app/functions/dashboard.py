import logging
from typing import Any

from fastapi import HTTPException

from app import dashboard_store
from app.models.dashboard import DashboardOut, DashboardPut, DashboardQuery, Role, WidgetPlacement
from app.registry import register
from app.vocab import Ward

log = logging.getLogger(__name__)


def _w(widget: str, **params: Any) -> WidgetPlacement:
    """A placement without empty params; never with as_of, so a pinned widget follows the replay date."""
    return WidgetPlacement(widget=widget, params={k: v for k, v in params.items() if v not in (None, [])})


def default_layout(role: Role | None, ward: Ward | None) -> list[WidgetPlacement]:
    """The layout a user starts with, per role (the Users table in #1). Each default links on to a
    full page: coverage to the answer page, the alert banner to the lab, the trend to Research and
    the spreading counts to infection control."""
    e_coli_tmp = {"organism": "Escherichia coli", "drug": "TMP", "specimen": "urine"}
    match role or "doctor":
        case "doctor":
            return [
                _w("CoverageRanking", ward=ward, infection_type="uti"),
                _w("AlertBanner"),
                _w("ResistanceTrend", **e_coli_tmp, ward=ward),
                _w("SpreadingCounts"),
            ]
        case "hygiene":
            return [
                _w("SpreadingCounts"),
                _w("AlertBanner"),
                _w("ResistanceTrend", organism="Staphylococcus aureus", drug="FOX", ward=ward),
            ]
        case "care_worker":
            wards = [ward] if ward else []
            return [_w("WardStatus", wards=wards), _w("SpreadingCounts", wards=wards)]
        case "lab":
            return [
                _w("AlertBanner"),
                _w("SamplingVolume", ward=ward),
                _w("ResistanceTrend", **e_coli_tmp, ward=ward),
            ]
        case _:  # researcher
            return [
                _w("ResistanceTrend", **e_coli_tmp, ward=ward),
                _w("WindowCompare", **e_coli_tmp, ward=ward),
            ]


def _default(q: DashboardQuery) -> DashboardOut:
    role = q.role or "doctor"
    return DashboardOut(user_id=q.user_id, role=role, layout=default_layout(role, q.ward))


@register(
    "get_dashboard",
    "A user's saved layout and role; without a saved layout, the default for the role and ward.",
    "/dashboard",
    DashboardQuery,
    DashboardOut,
    cache=False,
)
def get_dashboard(q: DashboardQuery) -> DashboardOut:
    try:
        saved = dashboard_store.store.get(q.user_id)
    except dashboard_store.StoreUnavailable:
        # A read must not break the screen: show the default layout and say why in the log.
        log.warning("dashboard read failed, serving the default layout", exc_info=True)
        saved = None
    return saved or _default(q)


@register("put_dashboard", "Save a user's layout.", "/dashboard", DashboardPut, DashboardOut, method="PUT")
def put_dashboard(q: DashboardPut) -> DashboardOut:
    out = DashboardOut(user_id=q.user_id, role=q.role, layout=q.layout)
    try:
        dashboard_store.store.put(out)
    except dashboard_store.StoreUnavailable as e:
        log.exception("dashboard save failed")
        raise HTTPException(status_code=503, detail="Could not save the dashboard, try again.") from e
    return out


@register(
    "reset_dashboard",
    "Forget a user's saved layout and return the default for the role and ward.",
    "/dashboard",
    DashboardQuery,
    DashboardOut,
    method="DELETE",
)
def reset_dashboard(q: DashboardQuery) -> DashboardOut:
    try:
        dashboard_store.store.delete(q.user_id)
    except dashboard_store.StoreUnavailable as e:
        log.exception("dashboard reset failed")
        raise HTTPException(status_code=503, detail="Could not reset the dashboard, try again.") from e
    return _default(q)
