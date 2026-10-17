"""Spreading and ward links: where the resistant types are, and which wards share patients.

Spreading: per ward and lab flag (MRSA, ESBL, VRE, CPE), the first isolates in the window against
the ward's own count over the 365 days before the window, scaled to the window length. A count is
above normal when it is implausibly high under a Poisson with that mean (p < SPREAD_P). Small
numbers hide percentages, never counts: one CPE on a ward that has never had one is above normal.
With under MIN_HISTORY_DAYS of history there is no baseline, so nothing is flagged.

Ward links: two wards are linked when the same patient has a culture on each within LINK_DAYS of
each other. The weight is the number of distinct such patients, counted over everything up to
as_of. Cross-ward warnings: a linked ward that has an active statistical or sentinel alert warns
the queried ward, provided the link is at least WARN_MIN_SHARE of the smaller ward's patients (the smaller
ward, because a hub like the ED would otherwise drown out its small neighbours). Most patients are
sampled on several wards, so this only drops the thinnest links, not most of them.
Everything is an aggregate: no patient id leaves this module.
"""

import threading
import weakref
from datetime import date, timedelta

import pandas as pd
from scipy.stats import poisson

from app.datalayer import alerts as A
from app.datalayer.store import DataStore, window_dates
from app.models.alerts import (
    SpreadingOut,
    SpreadingQuery,
    SpreadingRow,
    SpreadingSeriesOut,
    SpreadingSeriesQuery,
    SpreadingSeriesRow,
    WardLink,
    WardLinksOut,
    WardMix,
)
from app.models.common import WindowOut
from app.vocab import WARDS

FLAGS = {"MRSA": "mrsa", "ESBL": "esbl", "VRE": "vre", "CPE": "cpe"}
BASELINE_DAYS = 365
MIN_HISTORY_DAYS = 28  # a baseline shorter than one window says nothing
SPREAD_P = 0.01
LINK_DAYS = 30
WARN_MIN_SHARE = 0.05
WARN_TYPES = ("statistical", "sentinel")

_lock = threading.Lock()
_pairs: "weakref.WeakKeyDictionary[DataStore, pd.DataFrame]" = weakref.WeakKeyDictionary()
_patients: "weakref.WeakKeyDictionary[DataStore, pd.DataFrame]" = weakref.WeakKeyDictionary()


# ---- spreading ---------------------------------------------------------------------------------


def _flag_counts(store: DataStore, as_of: date, start: date, end: date) -> pd.DataFrame:
    """Flagged first isolates per ward (rows) and flag (columns) in [start, end]."""
    firsts = store.first_isolates(as_of, "custom", start, end)
    counts = {name: firsts.groupby("ward_code")[col].sum() for name, col in FLAGS.items()}
    return pd.DataFrame(counts).reindex(list(WARDS)).fillna(0).astype(int)


def spreading(store: DataStore, q: SpreadingQuery, window: WindowOut) -> SpreadingOut:
    start, end = window_dates(q.as_of, q.window, q.date_from, q.date_to)
    days = (end - start).days + 1
    now = _flag_counts(store, q.as_of, start, end)

    base_end = start - timedelta(days=1)
    first_day = store.tables.cultures["sample_date"].min().date()
    history = min(BASELINE_DAYS, (base_end - first_day).days + 1)
    if history >= MIN_HISTORY_DAYS:
        base = _flag_counts(store, base_end, base_end - timedelta(days=history - 1), base_end)
        normal = base * days / history
    else:
        normal = pd.DataFrame(0.0, index=now.index, columns=now.columns)

    rows = []
    for ward in q.wards or WARDS:
        for name in FLAGS:
            count, mean = int(now.at[ward, name]), float(normal.at[ward, name])
            above = history >= MIN_HISTORY_DAYS and count > 0 and poisson.sf(count - 1, mean) < SPREAD_P
            rows.append(SpreadingRow(ward=ward, phenotype=name, count=count, normal=round(mean, 2), above_normal=bool(above)))
    return SpreadingOut(window=window, rows=rows)


def spreading_series(store: DataStore, q: SpreadingSeriesQuery) -> SpreadingSeriesOut:
    """Flagged first isolates per ward, flag and 7-day block ending on as_of (oldest first).

    The last four blocks are the 28-day window of `spreading`; the typical weekly count is the
    ward's own 365 days before that window. Also the cultures and the organisms of the flagged
    isolates per ward in the last 4 weeks, for the ward detail.
    """
    weeks = q.weeks
    start = q.as_of - timedelta(days=7 * weeks - 1)
    firsts = store.first_isolates(q.as_of, "custom", start, q.as_of)
    block = ((firsts["sample_date"].dt.date.map(lambda d: (d - start).days)) // 7).clip(0, weeks - 1)

    win_start = q.as_of - timedelta(days=27)
    base_end = win_start - timedelta(days=1)
    first_day = store.tables.cultures["sample_date"].min().date()
    history = min(BASELINE_DAYS, (base_end - first_day).days + 1)
    base = (
        _flag_counts(store, base_end, base_end - timedelta(days=history - 1), base_end)
        if history >= MIN_HISTORY_DAYS
        else None
    )

    rows = []
    for ward in WARDS:
        in_ward = firsts["ward_code"] == ward
        for name, col in FLAGS.items():
            per = block[in_ward & (firsts[col] > 0)].value_counts()
            weekly = [int(per.get(i, 0)) for i in range(weeks)]
            normal = float(base.at[ward, name]) * 7 / history if base is not None else 0.0
            rows.append(SpreadingSeriesRow(ward=ward, phenotype=name, weekly=weekly, normal_weekly=round(normal, 2)))

    c = store.tables.cultures
    recent = c[(c["sample_date"] >= pd.Timestamp(win_start)) & (c["sample_date"] <= pd.Timestamp(q.as_of))]
    cultures = recent.groupby("ward_code").size()
    flagged = firsts[(firsts["sample_date"] >= pd.Timestamp(win_start)) & firsts[list(FLAGS.values())].gt(0).any(axis=1)]
    mix = flagged.groupby(["ward_code", "organism"]).size()
    wards = [
        WardMix(
            ward=w,
            cultures=int(cultures.get(w, 0)),
            organisms={o: int(n) for (ww, o), n in mix.items() if ww == w},
        )
        for w in WARDS
    ]
    week_starts = [start + timedelta(days=7 * i) for i in range(weeks)]
    return SpreadingSeriesOut(as_of=q.as_of, week_starts=week_starts, rows=rows, wards=wards)


# ---- ward links --------------------------------------------------------------------------------


def _link_pairs(store: DataStore) -> pd.DataFrame:
    """Every (patient, ward, other ward) with a culture on each within LINK_DAYS, and the later date."""
    with _lock:
        if store in _pairs:
            return _pairs[store]
    c = store.tables.cultures[["patient_id", "ward_code", "sample_date"]].drop_duplicates()
    m = c.merge(c, on="patient_id", suffixes=("", "_other"))
    gap = (m["sample_date"] - m["sample_date_other"]).abs()
    m = m[(m["ward_code"] != m["ward_code_other"]) & (gap <= pd.Timedelta(days=LINK_DAYS))]
    m = m.assign(seen=m[["sample_date", "sample_date_other"]].max(axis=1))
    m = m[["patient_id", "ward_code", "ward_code_other", "seen"]]
    with _lock:
        _pairs[store] = m
    return m


def _patient_counts(store: DataStore) -> pd.DataFrame:
    """(ward, first sample date) per patient, to count a ward's patients up to any as_of."""
    with _lock:
        if store in _patients:
            return _patients[store]
    c = store.tables.cultures.groupby(["ward_code", "patient_id"])["sample_date"].min().reset_index()
    with _lock:
        _patients[store] = c
    return c


def shared_patients(store: DataStore, ward: str, as_of: date) -> dict[str, int]:
    """Distinct patients sampled on `ward` and another ward within LINK_DAYS, by other ward."""
    m = _link_pairs(store)
    m = m[(m["ward_code"] == ward) & (m["seen"] <= pd.Timestamp(as_of))]
    return m.groupby("ward_code_other")["patient_id"].nunique().astype(int).to_dict()


def _ward_patients(store: DataStore, ward: str, as_of: date) -> int:
    p = _patient_counts(store)
    return int(((p["ward_code"] == ward) & (p["sample_date"] <= pd.Timestamp(as_of))).sum())


def _warning(store: DataStore, ward: str, other: str, shared: int, as_of: date) -> tuple[str | None, str | None, str | None]:
    """The most severe active alert on `other` as text, with its organism and phenotype."""
    active = [
        a for a in A.compute_alerts(store, as_of)
        if a.ward == other and a.type in WARN_TYPES and a.status == "active"
    ]  # compute_alerts is most severe first
    if not active:
        return None, None, None
    top = active[0]
    what = " ".join(x for x in (top.phenotype, top.organism) if x)
    more = f" (and {len(active) - 1} more)" if len(active) > 1 else ""
    text = (
        f"{other} has an active {what} alert{more}; {shared} patients were sampled on both "
        f"{other} and {ward} within {LINK_DAYS} days. Aggregate only."
    )
    return text, top.organism, top.phenotype


def ward_links(store: DataStore, ward: str, as_of: date) -> WardLinksOut:
    shared = shared_patients(store, ward, as_of)
    links = []
    for other, n in sorted(shared.items(), key=lambda kv: (-kv[1], kv[0])):
        text, organism, phenotype = (None, None, None)
        smaller = min(_ward_patients(store, ward, as_of), _ward_patients(store, other, as_of))
        if smaller and n / smaller >= WARN_MIN_SHARE:
            text, organism, phenotype = _warning(store, ward, other, n, as_of)
        links.append(WardLink(ward=other, shared_patients_30d=n, warning=text, organism=organism, phenotype=phenotype))
    return WardLinksOut(ward=ward, as_of=as_of, links=links)
