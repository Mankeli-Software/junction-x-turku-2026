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
from dataclasses import dataclass
from datetime import date, timedelta

import pandas as pd
from scipy.stats import poisson

from app.datalayer import signals as sig
from app.datalayer import trend as tr
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

EPISODE_GAP_DAYS = 14  # flagged weeks closer than this belong to one alert
HISTORY_DAYS = 365  # the signal needs a year of history for its hospital rate
MIN_SOLID_CASES = 5  # drug-only alerts with fewer resistant isolates are labelled too few
LOW_VOLUME_RATIO = 0.6  # ward sent under 60% of its usual cultures: the sample may be selective


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



# ---- statistical (one alert per ward x organism episode) ---------------------------------------


def _slug(organism: str) -> str:
    return organism.lower().replace(" ", "-")


def _monday(d: date) -> date:
    return week_start(d)


def _first_eval_day(store: DataStore) -> date:
    return store.tables.cultures["sample_date"].min().date() + timedelta(days=HISTORY_DAYS)


def warm_up(store: DataStore) -> None:
    """Compute every weekly signal once (about 12 s) so no request pays for it. Run in a thread."""
    sig.warm_up(store, _first_eval_day(store), store.tables.cultures["sample_date"].max().date())
    tr.trends(store, store.tables.cultures["sample_date"].max().date())


def _eval_days(store: DataStore, as_of: date) -> list[date]:
    """Sundays the signals are judged on, plus as_of itself, over the whole history."""
    first = _first_eval_day(store)
    days = []
    d = as_of - timedelta(days=(as_of.weekday() + 1) % 7)  # latest Sunday on or before as_of
    while d >= first:
        days.append(d)
        d -= WEEK
    if as_of not in days and as_of >= first:
        days.append(as_of)
    return sorted(days)


def _cases(store: DataStore, ward: str | None, organism: str, hits: list[sig.Hit], upto: date) -> pd.DataFrame:
    """Isolates of the organism (on one ward, or everywhere) up to `upto`, with is_case set.

    A case carries the flagged phenotype, or is resistant to one of the flagged drugs.
    """
    iso = store.isolates(upto)
    iso = iso[iso["organism"] == organism]
    if ward is not None:
        iso = iso[iso["ward_code"] == ward]
    hits = lead(hits)
    pheno = [h.name for h in hits if h.kind == "phenotype"]
    drugs = [h.name for h in hits if h.kind == "drug"]
    case = pd.Series(False, index=iso.index)
    for name in pheno:
        case |= iso[sig.PHENOTYPE_FLAGS[name]] == 1
    if drugs:
        sir = store.sir
        r_ids = set(sir.loc[(sir["organism"] == organism) & (sir["antibiotic_code"].isin(drugs)) & (sir["result"] == "R"), "isolate_id"])
        case |= iso["isolate_id"].isin(r_ids)
    return iso.assign(is_case=case)


def _ward_volume_ratio(store: DataStore, ward: str, as_of: date) -> float:
    """Cultures in the last 4 weeks over the ward's usual 4 weeks (mean of the 52 weeks before)."""
    c = store.tables.cultures
    c = c[(c["ward_code"] == ward) & (c["sample_date"] <= pd.Timestamp(as_of))]
    recent = int((c["sample_date"] > pd.Timestamp(as_of - timedelta(days=28))).sum())
    before = c[(c["sample_date"] <= pd.Timestamp(as_of - timedelta(days=28))) & (c["sample_date"] > pd.Timestamp(as_of - timedelta(days=28 + 364)))]
    usual = len(before) / 13 if len(before) else 0  # 52 weeks = 13 four-week periods
    return recent / usual if usual else 1.0


def _stat_verdict(store: DataStore, ward: str, hits: list[sig.Hit], as_of: date) -> tuple[str, str]:
    """Label from case mix and volume together, never volume alone."""
    pheno = [h for h in hits if h.kind == "phenotype"]
    ratio = _ward_volume_ratio(store, ward, as_of)
    if pheno:
        h = max(pheno, key=lambda x: x.r)
        return "likely_real", (
            f"{h.r} of {h.n} first isolates carry the {h.name} flag against {h.hospital:.1%} hospital-wide. "
            "The flag comes from the laboratory, so the signal does not depend on how many cultures were sent "
            f"(cultures on the ward are at {ratio:.0%} of usual)."
        )
    r = _top(hits).r
    if r < MIN_SOLID_CASES:
        return "too_few_cases", (
            f"Only {r} resistant first isolates behind the signal; {len(hits)} drugs are above the hospital "
            "rate but the count is too small to call it an outbreak."
        )
    if ratio < LOW_VOLUME_RATIO:
        return "possible_sampling_artefact", (
            f"{len(hits)} drugs are above the hospital rate, but the ward sent only {ratio:.0%} of its usual "
            "cultures, so the sample may be selective (for example only the sickest patients)."
        )
    return "likely_real", (
        f"{len(hits)} drugs are above the hospital rate together ({r} resistant first isolates at most) and "
        f"ward culture volume is {ratio:.0%} of usual, so the rise is not explained by sampling."
    )


def _onset(store: DataStore, ward: str, organism: str, hits: list[sig.Hit], first_day: date) -> date:
    """Date of the earliest case in the 4 weeks before the episode was first flagged."""
    cases = _cases(store, ward, organism, hits, first_day)
    cases = cases[cases["is_case"] & (cases["sample_date"] > pd.Timestamp(first_day - timedelta(days=sig.WINDOW_DAYS)))]
    return cases["sample_date"].min().date() if len(cases) else first_day


def lead(hits: list[sig.Hit]) -> list[sig.Hit]:
    """The hits that define the cases: the lab phenotype if one fired, otherwise the drugs."""
    pheno = [h for h in hits if h.kind == "phenotype"]
    return pheno or hits


def _top(hits: list[sig.Hit]) -> sig.Hit:
    return max(lead(hits), key=lambda h: (h.r, h.n))


@dataclass(frozen=True)
class Episode:
    """A run of flagged weeks for one ward x organism."""

    ward: str
    organism: str
    first_day: date  # first flagged evaluation
    last_day: date  # last flagged evaluation
    peak_day: date  # evaluation with the most cases
    hits: list[sig.Hit]  # the peak evaluation's hits
    first_hits: list[sig.Hit]  # the first flagged evaluation's hits (fixed once the episode starts)
    phenotypes: list[str]
    drugs: list[str]

    @property
    def key(self) -> str:
        return f"stat-{self.ward}-{_slug(self.organism)}-{_monday(self.first_day)}"


def _stat_episodes(store: DataStore, as_of: date) -> list[Episode]:
    flagged: dict[tuple[str, str], list[tuple[date, list[sig.Hit]]]] = {}
    for day in _eval_days(store, as_of):
        by: dict[tuple[str, str], list[sig.Hit]] = {}
        for h in sig.hits_on(store, day):
            by.setdefault((h.ward, h.organism), []).append(h)
        for g, hs in by.items():
            flagged.setdefault(g, []).append((day, hs))

    out = []
    for (ward, organism), items in flagged.items():
        runs: list[list[tuple[date, list[sig.Hit]]]] = []
        for it in items:
            if runs and (it[0] - runs[-1][-1][0]).days <= EPISODE_GAP_DAYS:
                runs[-1].append(it)
            else:
                runs.append([it])
        for run in runs:
            peak_day, hits = max(run, key=lambda it: (_top(it[1]).r, it[0]))  # the worst 4 weeks
            out.append(
                Episode(
                    ward, organism, run[0][0], run[-1][0], peak_day, hits, run[0][1],
                    sorted({h.name for _, hs in run for h in hs if h.kind == "phenotype"}),
                    sorted({h.name for _, hs in run for h in hs if h.kind == "drug"}),
                )
            )
    return out


def statistical_alerts(store: DataStore, as_of: date) -> list[Alert]:
    out = []
    for ep in _stat_episodes(store, as_of):
        top = _top(ep.hits)
        r, n = top.r, top.n
        what = f"{ep.phenotypes[0]} {ep.organism}" if ep.phenotypes else f"{ep.organism} resistance ({', '.join(ep.drugs)})"
        verdict, _ = _stat_verdict(store, ep.ward, ep.hits, ep.peak_day)
        out.append(
            Alert(
                alert_id=ep.key,
                type="statistical",
                severity="high" if ep.phenotypes else "medium",
                status="active" if ep.last_day == as_of else "resolved",
                ward=ep.ward,
                organism=ep.organism,
                phenotype=ep.phenotypes[0] if ep.phenotypes else None,
                drugs=ep.drugs,
                first_seen=_onset(store, ep.ward, ep.organism, ep.first_hits, ep.first_day),
                as_of=as_of,
                n_cases=r,
                summary=(
                    f"{what} on {ep.ward}: {r} of {n} first isolates in the 4 weeks to {ep.peak_day} (the peak), "
                    f"against {top.hospital:.1%} hospital-wide over 12 months."
                ),
                verdict=verdict,
            )
        )
    return out


def trend_alerts(store: DataStore, as_of: date) -> list[Alert]:
    out = []
    for t in tr.trends(store, as_of):
        out.append(
            Alert(
                alert_id=f"trend-{_slug(t.organism)}-{t.drug}",
                type="trend",
                severity="medium",
                status="active",
                ward=None,
                organism=t.organism,
                drugs=[t.drug],
                first_seen=t.detected_on,
                as_of=as_of,
                n_cases=t.resistant_last_12m,
                summary=(
                    f"{t.organism} {t.drug} resistance is rising {t.slope:.1f} points a year "
                    f"({t.first_rate:.1%} to {t.last_rate:.1%} over {t.months} months, hospital-wide)."
                ),
                verdict="likely_real",
            )
        )
    return out


DETECTORS: list[Callable[[DataStore, date], list[Alert]]] = [sentinel_alerts, missing_data_alerts, statistical_alerts, trend_alerts]

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
        if a.first_seen <= end and (a.first_seen >= start or a.status == "active")  # still-active alerts always show
        and (not q.ward or a.ward in (q.ward, None))  # hospital-wide alerts concern every ward
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
    if alert.type == "statistical":
        return _stat_detail(store, alert, as_of)
    if alert.type == "trend":
        return _trend_detail(store, alert, as_of)
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


def _stat_detail(store: DataStore, alert: Alert, as_of: date) -> AlertDetailOut:
    ep = next(e for e in _stat_episodes(store, as_of) if e.key == alert.alert_id)
    hits, peak_day = ep.hits, ep.peak_day
    weeks = _weeks_around(alert.first_seen, as_of)
    ward_cases = _cases(store, alert.ward, alert.organism, hits, as_of)
    all_cases = _cases(store, None, alert.organism, hits, as_of)
    w0 = pd.Timestamp(weeks[0])

    # Expected = the hospital rate before the window, applied to the ward's own isolates that week.
    before = all_cases[(all_cases["sample_date"] < w0) & (all_cases["sample_date"] >= w0 - pd.Timedelta(days=364))]
    hospital_rate = float(before["is_case"].mean()) if len(before) else 0.0
    by_week = ward_cases.groupby(ward_cases["sample_date"].dt.date.map(week_start))
    cases_w, isolates_w = by_week["is_case"].sum(), by_week.size()
    epi = [EpiPoint(week_start=w, cases=int(cases_w.get(w, 0)), expected=round(hospital_rate * int(isolates_w.get(w, 0)), 2)) for w in weeks]

    shown = ward_cases[ward_cases["is_case"] & (ward_cases["sample_date"] >= w0)].sort_values("sample_date", ascending=False)
    cases = [
        CaseRow(sample_date=r.sample_date.date(), ward=r.ward_code, specimen=r.specimen, organism=r.organism, phenotype=alert.phenotype)
        for r in shown.head(MAX_CASES).itertuples()
    ]
    volume = [VolumePoint(week_start=w, cultures=n) for w, n in zip(weeks, _weekly_cultures(store, alert.ward, weeks, as_of))]

    recent = all_cases[all_cases["sample_date"] > pd.Timestamp(as_of - timedelta(days=sig.WINDOW_DAYS))]
    share = recent.groupby("ward_code")["is_case"].agg(["sum", "size"])
    comparison = {w: round(float(row["sum"] / row["size"]), 3) for w, row in share.iterrows() if row["size"] >= 1}
    _, reason = _stat_verdict(store, alert.ward, hits, peak_day) if hits else (alert.verdict, alert.summary)
    return AlertDetailOut(
        alert=alert,
        epi_curve=epi,
        cases=cases,
        volume=volume,
        ward_comparison=comparison,
        verdict_reason=(
            f"{reason} Epi curve: cases per week against what the hospital rate would give for this ward's "
            "isolates. ward_comparison is the share of the organism's first isolates that are cases, per ward, "
            "over the last 4 weeks."
        ),
    )


def _trend_detail(store: DataStore, alert: Alert, as_of: date) -> AlertDetailOut:
    key = (alert.organism, alert.drugs[0])
    t = next(x for x in tr.trends(store, as_of) if (x.organism, x.drug) == key)
    series = tr._monthly(store).series[key]
    last = tr._last_complete_month(as_of)
    w = series[series.index <= last].tail(tr.MAX_MONTHS)
    epi = [EpiPoint(week_start=m.start_time.date(), cases=int(row["r"]), expected=round(float(row["n"]) * t.first_rate, 1)) for m, row in w.iterrows()]
    volume = [VolumePoint(week_start=m.start_time.date(), cultures=int(row["n"])) for m, row in w.iterrows()]

    firsts = store.first_isolates(as_of, "365d")
    sir = store.susceptibility(firsts[firsts["organism"] == alert.organism])
    sir = sir[sir["antibiotic_code"] == key[1]].merge(firsts[["isolate_id", "ward_code"]], on="isolate_id")
    by_ward = sir.groupby("ward_code")["result"].agg(lambda v: float((v == "R").mean()))
    return AlertDetailOut(
        alert=alert,
        epi_curve=epi,
        cases=[],
        volume=volume,
        ward_comparison={ward: round(rate, 3) for ward, rate in by_ward.items()},
        verdict_reason=(
            f"Mann-Kendall test on {t.months} monthly rates: tau {t.tau:.2f}, p {t.p:.1e}, Sen slope {t.slope:+.1f} points "
            f"a year, from {t.first_rate:.1%} (first 6 months) to {t.last_rate:.1%} (last 6). Tested hospital-wide with "
            f"about {int(w['n'].median())} first isolates a month, so it does not depend on sampling volume or on one outbreak month. "
            "One point per calendar month: week_start is the first day of the month, cases are resistant first isolates, "
            "expected is the same month at the starting rate and volume is first isolates tested. "
            "ward_comparison is the resistance rate per ward over the last 12 months."
        ),
    )
