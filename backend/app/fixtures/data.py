"""Fixtures for organisms, coverage and susceptibility (data person owns this file)."""

from datetime import date, timedelta

from app.datalayer.store import window_dates
from app.models.common import Estimate, WindowOut
from app.models.data import (
    SeriesOut,
    SirCounts,
    SusceptibilityOut,
    SusceptibilityRow,
    SusceptibilityWindowOut,
    WeeklyPoint,
)
from app.vocab import MIN_ISOLATES


def window_out(window: str, as_of: date, date_from: date | None, date_to: date | None) -> WindowOut:
    start, end = window_dates(as_of, window, date_from, date_to)  # never past as_of
    return WindowOut(window=window, as_of=as_of, date_from=start, date_to=end)


def estimate(value: float, n: int, level: str = "ward") -> Estimate:
    spread = 0.15 / (1 + n / 20)
    return Estimate(
        value=value,
        low=max(0.0, value - spread),
        high=min(1.0, value + spread),
        n=n,
        prior_level=level,  # type: ignore[arg-type]
        prior_weight=round(20 / (20 + n), 3),
        small_sample=n < MIN_ISOLATES,
    )


def _susceptibility_window(window: WindowOut, n: int, ward, specimen, organism, drug) -> SusceptibilityWindowOut:
    return SusceptibilityWindowOut(
        window=window,
        rows=[
            SusceptibilityRow(
                ward=ward,
                specimen=specimen or "urine",
                organism=organism or "Escherichia coli",
                drug=drug or "CRO",
                counts=SirCounts(s=n - n // 10, i=0, r=n // 10),
                resistance=estimate(0.1, n),
            )
        ],
    )


def susceptibility(recent: WindowOut, annual: WindowOut, ward, specimen, organism, drug) -> SusceptibilityOut:
    return SusceptibilityOut(
        recent=_susceptibility_window(recent, 30, ward, specimen, organism, drug),
        annual=_susceptibility_window(annual, 400, ward, specimen, organism, drug),
    )


def weekly_series(as_of: date, organism, drug, wards: list[str]) -> SeriesOut:
    start = as_of - timedelta(days=7 * 11)
    keys = [*(wards or ["URO"]), "hospital"]
    series = {
        k: [
            WeeklyPoint(
                week_start=start + timedelta(days=7 * i),
                n=12,
                r=1 + (i % 3),
                raw_rate=(1 + i % 3) / 12,
                shrunk_rate=0.1 + 0.01 * (i % 3),
                low=0.04,
                high=0.2,
            )
            for i in range(12)
        ]
        for k in keys
    }
    return SeriesOut(organism=organism, drug=drug, as_of=as_of, series=series)
