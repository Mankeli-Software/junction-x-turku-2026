"""Fixtures for alerts, volume, spreading and ward links (alerts person owns this file)."""

from datetime import date, timedelta

from app.models.alerts import (
    Alert,
    AlertDetailOut,
    AlertsOut,
    CaseRow,
    EpiPoint,
    SpreadingOut,
    SpreadingRow,
    VolumeOut,
    VolumePoint,
    VolumeRow,
    WardLink,
    WardLinksOut,
)
from app.models.common import WindowOut


def alert(as_of: date) -> Alert:
    return Alert(
        alert_id="A-ICU-MRSA-1",
        type="statistical",
        severity="high",
        status="active",
        ward="ICU",
        organism="Staphylococcus aureus",
        phenotype="MRSA",
        drugs=["FOX", "CLI"],
        first_seen=as_of - timedelta(days=14),
        as_of=as_of,
        n_cases=13,
        summary="MRSA share on ICU is 13 of 20 first isolates, far above the hospital rate.",
        verdict="likely_real",
    )


def alerts(as_of: date) -> AlertsOut:
    return AlertsOut(as_of=as_of, alerts=[alert(as_of)])


def _weeks(as_of: date, n: int = 8) -> list[date]:
    return [as_of - timedelta(days=7 * (n - 1 - i)) for i in range(n)]


def alert_detail(as_of: date) -> AlertDetailOut:
    weeks = _weeks(as_of)
    return AlertDetailOut(
        alert=alert(as_of),
        epi_curve=[EpiPoint(week_start=w, cases=i, expected=1.0) for i, w in enumerate(weeks)],
        cases=[
            CaseRow(
                sample_date=as_of - timedelta(days=i),
                ward="ICU",
                specimen="wound",
                organism="Staphylococcus aureus",
                phenotype="MRSA",
            )
            for i in range(3)
        ],
        volume=[VolumePoint(week_start=w, cultures=20) for w in weeks],
        ward_comparison={"ICU": 0.65, "SURG": 0.08, "MED-A": 0.05},
        verdict_reason="Culture volume is flat while MRSA cases rise, so this is not a sampling artefact.",
    )


def volume(window: WindowOut, ward, specimen) -> VolumeOut:
    weeks = _weeks(window.as_of, 4)
    return VolumeOut(
        window=window,
        rows=[
            VolumeRow(
                ward=ward or "URO",
                specimen=specimen or "urine",
                points=[VolumePoint(week_start=w, cultures=30) for w in weeks],
                total=120,
                baseline_weekly=28.0,
            )
        ],
    )


def spreading(window: WindowOut, wards: list[str]) -> SpreadingOut:
    return SpreadingOut(
        window=window,
        rows=[
            SpreadingRow(ward=w, phenotype=p, count=c, normal=n, above_normal=c > n)  # type: ignore[arg-type]
            for w in (wards or ["ICU", "URO"])
            for p, c, n in [("MRSA", 4, 1.0), ("ESBL", 2, 2.0)]
        ],
    )


def ward_links(ward: str, as_of: date) -> WardLinksOut:
    return WardLinksOut(
        ward=ward,  # type: ignore[arg-type]
        as_of=as_of,
        links=[
            WardLink(
                ward="ED",
                shared_patients_30d=291,
                warning="ESBL E. coli on ED is above normal. Aggregate only.",
                organism="Escherichia coli",
                phenotype="ESBL",
            ),
            WardLink(ward="GER", shared_patients_30d=120),
        ],
    )
