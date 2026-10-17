"""Alerts computed from the data: sentinel (CPE, VRE) and missing data.

Statistical and trend alerts (ALERT-2) plug into DETECTORS. Everything is a pure function of the
data up to as_of, so the replay slider shows exactly what the tool would have shown that day.

Rules, and why:
- Sentinel: any single CPE or VRE isolate, every isolate counted (no first-isolate rule, no
  minimum sample size). Not "carbapenem-resistant" in general: 92 of the 104 meropenem-resistant
  isolates are Pseudomonas, so that rule would be noise. The phenotype flags come from the lab.
- Missing data: a ward whose weekly culture count falls to at most MISSING_MAX_RATIO of its own
  seasonal baseline and is implausible under that baseline (Poisson, p < MISSING_MAX_P). The
  ratio keeps ordinary slow weeks out; the p-value keeps small wards from firing on noise. A week
  is judged only once it is over (Sunday), and consecutive weeks merge into one alert.
"""

import weakref
from collections import OrderedDict
from collections.abc import Callable
from datetime import date, timedelta

import pandas as pd
from scipy.stats import poisson

from app.datalayer.store import DataStore, window_dates
from app.datalayer.volume import (
    BASELINE_RECENT_WEEKS,
    WEEK,
    expected_weekly,
    last_complete_week_start,
    week_start,
    weekly_volume,
)
from app.models.alerts import (
    Alert,
    AlertDetailOut,
    AlertsOut,
    AlertsQuery,
    CaseRow,
    EpiPoint,
    VolumePoint,
)
from app.vocab import WARDS

ACTIVE_DAYS = 28  # an alert is "active" while its first_seen is this recent
MISSING_MAX_RATIO = 0.3
MISSING_MAX_P = 1e-6
MISSING_MIN_EXPECTED = 5.0  # wards too small for a weekly count to mean anything are skipped
EPI_WEEKS_BEFORE = 12
EPI_WEEKS_AFTER = 12
MAX_CASES = 50

# phenotype flag column -> (severity, drugs the phenotype implies resistance to)
SENTINEL = {"CPE": ("cpe", "critical", ["MEM"]), "VRE": ("vre", "high", ["VAN"])}
SEVERITY_RANK: dict[str, int] = {"critical": 0, "high": 1, "medium": 2, "low": 3}


class UnknownAlert(KeyError):
    pass


def _status(first_seen: date, as_of: date) -> str:
    # Acknowledged needs stored state; until alerts are persisted every alert is active or resolved.
    return "active" if (as_of - first_seen).days < ACTIVE_DAYS else "resolved"


# ---- detectors ---------------------------------------------------------------------------------


def sentinel_alerts(store: DataStore, as_of: date) -> list[Alert]:
    iso = store.isolates(as_of)
    out = []
    for pheno, (col, severity, drugs) in SENTINEL.items():
        for r in iso[iso[col] == 1].itertuples():
            seen = r.sample_date.date()
            out.append(
                Alert(
                    alert_id=f"sentinel-{r.isolate_id}",
                    type="sentinel",
                    severity=severity,
                    status=_status(seen, as_of),
                    ward=r.ward_code,
                    organism=r.organism,
                    phenotype=pheno,
                    drugs=drugs,
                    first_seen=seen,
                    as_of=as_of,
                    n_cases=1,
                    summary=(
                        f"{pheno} {r.organism} isolated from {r.specimen} on {r.ward_code} on {seen}. "
                        f"A single {pheno} isolate is always reported."
                    ),
                    verdict="likely_real",
                )
            )
    return out


def _missing_weeks(store: DataStore, as_of: date) -> list[tuple[str, int, float]]:
    """(ward, week index, expected) for every finished week that is far below its baseline."""
    wv = weekly_volume(store)
    last = min(wv.index_of(last_complete_week_start(as_of)), wv.n_weeks - 1)
    hits = []
    for ward in WARDS:
        series = wv.ward_series(ward)
        for idx in range(BASELINE_RECENT_WEEKS, last + 1):
            exp = expected_weekly(series, idx)
            if exp is None or exp < MISSING_MIN_EXPECTED:
                continue
            seen = int(series[idx])
            if seen <= MISSING_MAX_RATIO * exp and poisson.cdf(seen, exp) < MISSING_MAX_P:
                hits.append((ward, idx, exp))
    return hits


def missing_data_alerts(store: DataStore, as_of: date) -> list[Alert]:
    wv = weekly_volume(store)
    out = []
    by_ward: dict[str, list[tuple[int, float]]] = {}
    for ward, idx, exp in _missing_weeks(store, as_of):
        by_ward.setdefault(ward, []).append((idx, exp))
    for ward, hits in by_ward.items():
        series = wv.ward_series(ward)
        runs: list[list[tuple[int, float]]] = []
        for h in hits:  # merge consecutive weeks into one alert
            if runs and h[0] == runs[-1][-1][0] + 1:
                runs[-1].append(h)
            else:
                runs.append([h])
        for run in runs:
            first = wv.week_at(run[0][0])
            got = int(sum(series[i] for i, _ in run))
            want = round(sum(e for _, e in run))
            weeks = len(run)
            out.append(
                Alert(
                    alert_id=f"missing-{ward}-{first}",
                    type="missing_data",
                    severity="medium",
                    status=_status(first, as_of),
                    ward=ward,
                    first_seen=first,
                    as_of=as_of,
                    n_cases=got,  # cultures actually received in the gap
                    summary=(
                        f"{ward} sent {got} cultures in {'the week' if weeks == 1 else f'{weeks} weeks'} "
                        f"from {first}; about {want} were expected for this time of year."
                    ),
                    verdict="possible_sampling_artefact",
                )
            )
    return out


DETECTORS: list[Callable[[DataStore, date], list[Alert]]] = [sentinel_alerts, missing_data_alerts]

_cache: "weakref.WeakKeyDictionary[DataStore, OrderedDict[date, list[Alert]]]" = weakref.WeakKeyDictionary()
CACHE_SIZE = 64


def compute_alerts(store: DataStore, as_of: date) -> list[Alert]:
    """Every alert known on as_of, most severe first, then newest."""
    per_store = _cache.setdefault(store, OrderedDict())
    if as_of in per_store:
        per_store.move_to_end(as_of)
        return per_store[as_of]
    alerts = [a for detect in DETECTORS for a in detect(store, as_of)]
    alerts.sort(key=lambda a: (SEVERITY_RANK[a.severity], -a.first_seen.toordinal(), a.alert_id))
    per_store[as_of] = alerts
    if len(per_store) > CACHE_SIZE:
        per_store.popitem(last=False)
    return alerts


def list_alerts(store: DataStore, q: AlertsQuery) -> AlertsOut:
    start, end = window_dates(q.as_of, q.window, q.date_from, q.date_to)
    keep = [
        a
        for a in compute_alerts(store, q.as_of)
        if start <= a.first_seen <= end
        and (not q.ward or a.ward == q.ward)
        and (not q.severity or a.severity == q.severity)
        and (not q.status or a.status == q.status)
    ]
    return AlertsOut(as_of=q.as_of, alerts=keep)


# ---- detail ------------------------------------------------------------------------------------


def _weekly_cultures(store: DataStore, ward: str, weeks: list[date], as_of: date) -> list[int]:
    """Cultures per week for a ward, counting nothing after as_of."""
    c = store.tables.cultures
    c = c[(c["ward_code"] == ward) & (c["sample_date"] <= pd.Timestamp(as_of))]
    per_week = c.groupby(c["sample_date"].dt.date.map(week_start)).size()
    return [int(per_week.get(w, 0)) for w in weeks]


def _weeks_around(first_seen: date, as_of: date) -> list[date]:
    w0 = week_start(first_seen)
    lo = w0 - WEEK * EPI_WEEKS_BEFORE
    hi = min(w0 + WEEK * EPI_WEEKS_AFTER, week_start(as_of))
    return [lo + WEEK * i for i in range((hi - lo) // WEEK + 1)]


def alert_detail(store: DataStore, alert_id: str, as_of: date) -> AlertDetailOut:
    alert = next((a for a in compute_alerts(store, as_of) if a.alert_id == alert_id), None)
    if alert is None:
        raise UnknownAlert(alert_id)
    if alert.type == "sentinel":
        return _sentinel_detail(store, alert, as_of)
    return _missing_detail(store, alert, as_of)


def _sentinel_detail(store: DataStore, alert: Alert, as_of: date) -> AlertDetailOut:
    col = SENTINEL[alert.phenotype][0]
    iso = store.isolates(as_of)
    flagged = iso[iso[col] == 1]
    here = flagged[flagged["ward_code"] == alert.ward]
    weeks = _weeks_around(alert.first_seen, as_of)

    per_week = here.groupby(here["sample_date"].dt.date.map(week_start)).size()
    before = here[here["sample_date"] < pd.Timestamp(weeks[0])]
    history_weeks = max((weeks[0] - week_start(iso["sample_date"].min().date())).days // 7, 1)
    typical = round(len(before) / history_weeks, 3)  # weekly rate of this phenotype here, before the window
    epi = [EpiPoint(week_start=w, cases=int(per_week.get(w, 0)), expected=typical) for w in weeks]

    recent = here[here["sample_date"] >= pd.Timestamp(weeks[0])].sort_values("sample_date", ascending=False)
    cases = [
        CaseRow(
            sample_date=r.sample_date.date(),
            ward=r.ward_code,
            specimen=r.specimen,
            organism=r.organism,
            phenotype=alert.phenotype,
        )
        for r in recent.head(MAX_CASES).itertuples()
    ]
    volume = [VolumePoint(week_start=w, cultures=n) for w, n in zip(weeks, _weekly_cultures(store, alert.ward, weeks, as_of))]

    # Cases per 1,000 cultures by ward over the year up to as_of, so a ward is not flagged for being big.
    since = pd.Timestamp(as_of - timedelta(days=364))
    cult = store.tables.cultures
    cult = cult[(cult["sample_date"] >= since) & (cult["sample_date"] <= pd.Timestamp(as_of))]
    cases_y = flagged[flagged["sample_date"] >= since].groupby("ward_code").size()
    cult_y = cult.groupby("ward_code").size()
    comparison = {w: round(1000 * int(cases_y.get(w, 0)) / int(cult_y[w]), 2) for w in WARDS if w in cult_y.index}

    return AlertDetailOut(
        alert=alert,
        epi_curve=epi,
        cases=cases,
        volume=volume,
        ward_comparison=comparison,
        verdict_reason=(
            f"{alert.phenotype} is a laboratory-confirmed flag on the isolate, so one isolate is enough: "
            "it does not depend on how many cultures the ward sent. "
            f"ward_comparison is {alert.phenotype} isolates per 1,000 cultures over the last 12 months."
        ),
    )


def _missing_detail(store: DataStore, alert: Alert, as_of: date) -> AlertDetailOut:
    wv = weekly_volume(store)
    series = wv.ward_series(alert.ward)
    last = min(wv.index_of(last_complete_week_start(as_of)), wv.n_weeks - 1)
    first_idx = wv.index_of(alert.first_seen)
    lo = max(0, first_idx - EPI_WEEKS_BEFORE)
    hi = min(first_idx + EPI_WEEKS_AFTER, last)  # finished weeks only
    epi, volume = [], []
    for idx in range(lo, hi + 1):
        exp = expected_weekly(series, idx)
        epi.append(EpiPoint(week_start=wv.week_at(idx), cases=int(series[idx]), expected=round(exp, 1) if exp else 0.0))
        volume.append(VolumePoint(week_start=wv.week_at(idx), cultures=int(series[idx])))

    # Observed / expected for every ward in the first missing week: is it this ward only?
    ratios = {}
    for w in WARDS:
        s = wv.ward_series(w)
        e = expected_weekly(s, first_idx)
        if e and e >= MISSING_MIN_EXPECTED:
            ratios[w] = round(float(s[first_idx]) / e, 2)
    others = [v for w, v in ratios.items() if w != alert.ward]
    normal = sum(1 for v in others if v >= 0.6)
    if others and normal >= 0.75 * len(others):
        scope = (
            f"{normal} of the other {len(others)} wards sent normal volume that week, "
            "so this is specific to the ward's sample flow, not a hospital-wide pattern."
        )
    else:
        scope = "Several other wards were also low that week, which points to a reporting problem."
    return AlertDetailOut(
        alert=alert,
        epi_curve=epi,
        cases=[],
        volume=volume,
        ward_comparison=ratios,
        verdict_reason=(
            "No clinical signal: the ward stopped sending cultures, so any resistance figure for it is "
            f"missing, not good. {scope} ward_comparison is cultures received divided by cultures expected, "
            "per ward, for the first missing week."
        ),
    )
