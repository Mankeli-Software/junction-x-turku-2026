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
    out = fx.alerts(q.as_of)
    out.alerts = [
        a
        for a in out.alerts
        if (not q.ward or a.ward == q.ward)
        and (not q.severity or a.severity == q.severity)
        and (not q.status or a.status == q.status)
    ]
    return out


@register(
    "get_alert_detail",
    "One alert with epi curve, cases, sampling volume, ward comparison and verdict.",
    "/alerts/detail",
    AlertDetailQuery,
    AlertDetailOut,
)
def get_alert_detail(q: AlertDetailQuery) -> AlertDetailOut:
    return fx.alert_detail(q.as_of)


@register("get_volume", "Culture counts by ward and specimen, for sampling-volume checks.", "/volume", VolumeQuery, VolumeOut)
def get_volume(q: VolumeQuery) -> VolumeOut:
    return fx.volume(_win(q), q.ward, q.specimen)


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
