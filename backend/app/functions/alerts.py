from fastapi import HTTPException

from app.datalayer import alerts as real_alerts
from app.datalayer import volume as real_volume
from app.datalayer.store import get_store
from app.fixtures import alerts as fx
from app.fixtures.data import window_out
from app.models.alerts import (
    AlertDetailOut,
    AlertDetailQuery,
    AlertsOut,
    AlertsQuery,
    SpreadingOut,
    SpreadingQuery,
    VolumeOut,
    VolumeQuery,
    WardLinksOut,
    WardLinksQuery,
)
from app.registry import register


def _win(q):
    return window_out(q.window, q.as_of, q.date_from, q.date_to)


@register("get_alerts", "Active and past alerts, filterable by ward, severity and status.", "/alerts", AlertsQuery, AlertsOut)
def get_alerts(q: AlertsQuery) -> AlertsOut:
    return real_alerts.list_alerts(get_store(), q)


@register(
    "get_alert_detail",
    "One alert with epi curve, cases, sampling volume, ward comparison and verdict.",
    "/alerts/detail",
    AlertDetailQuery,
    AlertDetailOut,
)
def get_alert_detail(q: AlertDetailQuery) -> AlertDetailOut:
    try:
        return real_alerts.alert_detail(get_store(), q.alert_id, q.as_of)
    except real_alerts.UnknownAlert as e:
        raise HTTPException(status_code=404, detail=f"No alert {q.alert_id} on {q.as_of}") from e


@register("get_volume", "Culture counts by ward and specimen, for sampling-volume checks.", "/volume", VolumeQuery, VolumeOut)
def get_volume(q: VolumeQuery) -> VolumeOut:
    return real_volume.volume(get_store(), q, _win(q))


@register(
    "get_spreading",
    "MRSA, ESBL, VRE and CPE counts per ward against normal.",
    "/spreading",
    SpreadingQuery,
    SpreadingOut,
)
def get_spreading(q: SpreadingQuery) -> SpreadingOut:
    return fx.spreading(_win(q), list(q.wards))


@register(
    "get_ward_links",
    "Linked wards and cross-ward warnings, aggregates only.",
    "/ward-links",
    WardLinksQuery,
    WardLinksOut,
)
def get_ward_links(q: WardLinksQuery) -> WardLinksOut:
    return fx.ward_links(q.ward, q.as_of)
