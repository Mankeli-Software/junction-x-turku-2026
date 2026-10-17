"""Slow drift in resistance: a monthly trend test per organism x drug, hospital-wide.

A CUSUM or a 4-week window cannot see a rise of two points a year; this test looks at up to 36
months of first isolates. Per month and per organism x drug it takes R / n (first isolate per
patient x organism x specimen within the calendar month, all wards), then:
- Mann-Kendall test (Kendall's tau of the monthly rate against time): rank-based, so one
  outbreak month among 36 cannot create a trend on its own.
- Sen slope (median of pairwise slopes, in points per year) as the size of the change.
It alerts on a rise only, when p is below FAMILY_ALPHA split over the pairs tested (Bonferroni) and
the slope is at least MIN_SLOPE points a year. Falls are good news and are not alerted.
Only complete months up to as_of are used. Per-ward trend tests are too weak at these volumes.
"""

import weakref
from dataclasses import dataclass
from datetime import date

import numpy as np
import pandas as pd
from scipy.stats import kendalltau, theilslopes

from app.datalayer.store import DataStore
from app.vocab import DEFAULT_AS_OF

MAX_MONTHS = 36
MIN_MONTHS = 18
MIN_MEDIAN_N = 15  # first isolates per month; thinner series have no power
FAMILY_ALPHA = 0.01
MIN_SLOPE = 1.0  # points per year


@dataclass(frozen=True)
class Trend:
    organism: str
    drug: str
    months: int
    tau: float
    p: float
    slope: float  # points per year
    first_rate: float  # mean of the first 6 months in the window
    last_rate: float  # mean of the last 6 months
    resistant_last_12m: int  # resistant first isolates in the last 12 months
    detected_on: date  # end of the first month this trend was significant, in an unbroken run to as_of


class _Monthly:
    """Monthly (n, r) per organism x drug for the whole store."""

    def __init__(self, store: DataStore):
        iso = store.isolates(DEFAULT_AS_OF)[["isolate_id", "patient_id", "organism", "specimen", "sample_date", "culture_id", "isolate_no"]].copy()
        iso["month"] = iso["sample_date"].dt.to_period("M")
        iso = iso.sort_values(["sample_date", "culture_id", "isolate_no"])
        first = iso.drop_duplicates(["month", "patient_id", "organism", "specimen"])
        sir = store.tables.susceptibility[["isolate_id", "antibiotic_code", "result"]]
        m = first.merge(sir, on="isolate_id")
        m["r"] = (m["result"] == "R").astype(int)
        g = m.groupby(["organism", "antibiotic_code", "month"]).agg(n=("r", "size"), r=("r", "sum"))
        self.series: dict[tuple[str, str], pd.DataFrame] = {k: v.droplevel([0, 1]) for k, v in g.groupby(level=[0, 1])}
        self.significant: dict[pd.Period, dict[tuple[str, str], tuple[float, float, float, int]]] = {}


_cache: "weakref.WeakKeyDictionary[DataStore, _Monthly]" = weakref.WeakKeyDictionary()


def _monthly(store: DataStore) -> _Monthly:
    if store not in _cache:
        _cache[store] = _Monthly(store)
    return _cache[store]


def _last_complete_month(as_of: date) -> pd.Period:
    this = pd.Period(as_of, "M")
    return this if as_of == this.end_time.date() else this - 1


def _test(df: pd.DataFrame, upto: pd.Period) -> tuple[float, float, float, int] | None:
    """(tau, p, slope in points/year, months) for the trailing window ending at `upto`, or None."""
    w = df[df.index <= upto].tail(MAX_MONTHS)
    if len(w) < MIN_MONTHS or w["n"].median() < MIN_MEDIAN_N:
        return None
    rate = (w["r"] / w["n"]).to_numpy()
    t = np.arange(len(w))
    tau, p = kendalltau(t, rate)
    if np.isnan(tau):
        return None
    slope = float(theilslopes(rate * 100, t)[0] * 12)
    return float(tau), float(p), slope, len(w)


def _significant(store: DataStore, upto: pd.Period) -> dict[tuple[str, str], tuple[float, float, float, int]]:
    monthly = _monthly(store)
    if upto not in monthly.significant:
        tested = {k: r for k, df in monthly.series.items() if (r := _test(df, upto)) is not None}
        threshold = FAMILY_ALPHA / max(len(tested), 1)
        monthly.significant[upto] = {k: r for k, r in tested.items() if r[1] < threshold and r[2] >= MIN_SLOPE}
    return monthly.significant[upto]


def trends(store: DataStore, as_of: date) -> list[Trend]:
    """Rising trends significant on as_of, each with the month it first became significant."""
    last = _last_complete_month(as_of)
    out = []
    now = _significant(store, last)
    series = _monthly(store).series
    for key, (tau, p, slope, months) in now.items():
        first = last
        while True:  # walk back while the run stays significant
            prev = first - 1
            if key in _significant(store, prev):
                first = prev
            else:
                break
        w = series[key][series[key].index <= last].tail(MAX_MONTHS)
        rate = w["r"] / w["n"]
        out.append(
            Trend(key[0], key[1], months, tau, p, slope, float(rate.head(6).mean()), float(rate.tail(6).mean()), int(w['r'].tail(12).sum()), first.end_time.date())
        )
    return sorted(out, key=lambda t: (t.p, t.organism, t.drug))
