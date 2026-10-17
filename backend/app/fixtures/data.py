"""Fixtures for organisms, coverage and susceptibility (data person owns this file)."""

from datetime import date, timedelta

from app.models.common import Estimate, WindowOut
from app.models.data import (
    CoverageOut,
    CoverageWindowSet,
    OrganismMixOut,
    OrganismShare,
    RegimenCoverage,
    SeriesOut,
    SirCounts,
    SusceptibilityOut,
    SusceptibilityRow,
    SusceptibilityWindowOut,
    WeeklyPoint,
)
from app.vocab import MIN_ISOLATES, WINDOW_DAYS


def window_out(window: str, as_of: date, date_from: date | None, date_to: date | None) -> WindowOut:
    if window == "custom":
        assert date_from and date_to
        return WindowOut(window=window, as_of=as_of, date_from=date_from, date_to=date_to)
    return WindowOut(
        window=window, as_of=as_of, date_from=as_of - timedelta(days=WINDOW_DAYS[window] - 1), date_to=as_of
    )


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


def organism_mix(as_of: date, window: WindowOut, ward, specimen) -> OrganismMixOut:
    return OrganismMixOut(
        window=window,
        ward=ward,
        specimen=specimen or "urine",
        n_first_isolates=48,
        organisms=[
            OrganismShare(organism="Escherichia coli", share=0.57, n=27),
            OrganismShare(organism="Klebsiella pneumoniae", share=0.11, n=5),
            OrganismShare(organism="Enterococcus faecalis", share=0.32, n=16),
        ],
    )


def _coverage_set(window: WindowOut, n: int) -> CoverageWindowSet:
    return CoverageWindowSet(
        window=window,
        n_first_isolates=n,
        options=[
            RegimenCoverage(regimen=["NIT"], coverage=estimate(0.91, n), covers_target=True),
            RegimenCoverage(regimen=["CRO"], coverage=estimate(0.88, n), covers_target=False),
            RegimenCoverage(regimen=["MEM"], coverage=estimate(0.99, n), covers_target=True),
        ],
        narrowest_effective=["NIT"],
    )


def coverage(recent: WindowOut, annual: WindowOut, ward, specimen) -> CoverageOut:
    return CoverageOut(
        ward=ward,
        specimen=specimen or "urine",
        recent=_coverage_set(recent, 48),
        annual=_coverage_set(annual, 520),
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
