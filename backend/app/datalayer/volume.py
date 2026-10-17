"""Culture counts per ward, specimen and week, and the seasonal baseline built on them.

Counts are cultures (every sample, positive or not), so a ward that stops sending samples shows
up here even though it never produces an isolate. Weeks run Monday to Sunday.
"""

import weakref
from datetime import date, timedelta

import numpy as np
import pandas as pd

from app.datalayer.store import DataStore, window_dates
from app.models.alerts import VolumeOut, VolumePoint, VolumeQuery, VolumeRow
from app.models.common import WindowOut
from app.vocab import SPECIMENS, WARDS

WEEK = timedelta(days=7)
YEAR_WEEKS = 52
BASELINE_RECENT_WEEKS = 12  # the level the seasonal profile is scaled to
SEASON_HALF_WIDTH = 2  # same ISO week +- 2 in earlier years
BASELINE_HISTORY_WEEKS = 52  # get_volume baseline_weekly: mean over this many weeks before the window


def week_start(d: date) -> date:
    return d - timedelta(days=d.weekday())


def last_complete_week_start(as_of: date) -> date:
    """Start of the latest Monday-Sunday week that is finished on as_of (inclusive)."""
    this = week_start(as_of)
    return this if as_of.weekday() == 6 else this - WEEK


class WeeklyVolume:
    """Weekly culture counts for one store: a (weeks x wards x specimens) array."""

    def __init__(self, store: DataStore):
        c = store.tables.cultures
        self.first_week = week_start(c["sample_date"].min().date())
        last = week_start(c["sample_date"].max().date())
        self.n_weeks = (last - self.first_week) // WEEK + 1
        w = ((c["sample_date"] - pd.Timestamp(self.first_week)).dt.days // 7).to_numpy()
        wi = c["ward_code"].map({k: i for i, k in enumerate(WARDS)}).to_numpy()
        si = c["specimen"].map({k: i for i, k in enumerate(SPECIMENS)}).to_numpy()
        self.counts = np.zeros((self.n_weeks, len(WARDS), len(SPECIMENS)), dtype=np.int64)
        np.add.at(self.counts, (w, wi, si), 1)

    def index_of(self, week: date) -> int:
        return (week - self.first_week) // WEEK

    def week_at(self, idx: int) -> date:
        return self.first_week + WEEK * idx

    def ward_series(self, ward: str) -> np.ndarray:
        """All specimens summed, one count per week."""
        return self.counts[:, WARDS.index(ward), :].sum(axis=1)


_cache: "weakref.WeakKeyDictionary[DataStore, WeeklyVolume]" = weakref.WeakKeyDictionary()


def weekly_volume(store: DataStore) -> WeeklyVolume:
    if store not in _cache:
        _cache[store] = WeeklyVolume(store)
    return _cache[store]


def expected_weekly(series: np.ndarray, idx: int) -> float | None:
    """What week `idx` should look like, using only weeks before it, or None without history.

    Seasonal profile: the median of the same week +-2 in each earlier year, scaled by how the
    last 12 weeks compare with the same 12 weeks a year earlier (so growth or a quieter year is
    respected). The median keeps an old gap from dragging the baseline down. With no earlier
    year, the median of the last 12 weeks.
    """
    n = BASELINE_RECENT_WEEKS
    if idx < n:
        return None
    recent = series[idx - n : idx]
    level = float(np.median(recent))
    profiles, ratios = [], []
    for y in (1, 2):
        shift = YEAR_WEEKS * y
        lo, hi = idx - shift - SEASON_HALF_WIDTH, idx - shift + SEASON_HALF_WIDTH + 1
        if lo < 0:
            continue
        profiles.append(float(np.median(series[lo:hi])))
        if idx - shift - n >= 0:
            ratios.append(float(np.median(series[idx - shift - n : idx - shift])))
    if not profiles:
        return level
    seasonal = float(np.mean(profiles))
    last_year_level = float(np.mean(ratios)) if ratios else 0.0
    scale = level / last_year_level if last_year_level > 0 else 1.0
    return seasonal * scale


def volume(store: DataStore, q: VolumeQuery, window: WindowOut) -> VolumeOut:
    """Weekly culture counts for the window, per ward and specimen.

    Weeks at the window edges are clipped to the window, so the first and last bar can be partial.
    baseline_weekly is the mean over the 52 complete weeks before the window (0 without history).
    """
    wv = weekly_volume(store)
    start, end = window_dates(q.as_of, q.window, q.date_from, q.date_to)
    cultures = store.tables.cultures
    in_win = cultures[(cultures["sample_date"] >= pd.Timestamp(start)) & (cultures["sample_date"] <= pd.Timestamp(end))]
    weeks = [week_start(start) + WEEK * i for i in range((week_start(end) - week_start(start)) // WEEK + 1)]
    base_hi = max(0, wv.index_of(week_start(start)))  # exclusive: weeks fully before the window's first week
    base_lo = max(0, base_hi - BASELINE_HISTORY_WEEKS)

    rows = []
    for ward in [q.ward] if q.ward else WARDS:
        for spec in [q.specimen] if q.specimen else SPECIMENS:
            sub = in_win[(in_win["ward_code"] == ward) & (in_win["specimen"] == spec)]
            per_week = sub.groupby(sub["sample_date"].dt.date.map(week_start)).size()
            points = [VolumePoint(week_start=w, cultures=int(per_week.get(w, 0))) for w in weeks]
            hist = wv.counts[base_lo:base_hi, WARDS.index(ward), SPECIMENS.index(spec)]
            rows.append(
                VolumeRow(
                    ward=ward,
                    specimen=spec,
                    points=points,
                    total=int(sum(p.cultures for p in points)),
                    baseline_weekly=round(float(hist.mean()), 2) if len(hist) else 0.0,
                )
            )
    return VolumeOut(window=window, rows=rows)
