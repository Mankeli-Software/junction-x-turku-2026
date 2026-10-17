from datetime import timedelta

from app.datalayer import coverage as cov
from app.datalayer import susceptibility as susc
from app.datalayer.store import get_store, window_dates
from app.fixtures import data as fx
from app.models.common import WindowOut
from app.models.data import (
    CoverageOut,
    CoverageQuery,
    CoverageWindowSet,
    OrganismMixOut,
    OrganismMixQuery,
    OrganismShare,
    RegimenCoverage,
    SeriesOut,
    SeriesQuery,
    SirCounts,
    SusceptibilityOut,
    SusceptibilityQuery,
    SusceptibilityRow,
    SusceptibilityWindowOut,
    WeeklyPoint,
)
from app.registry import register
from app.vocab import INFECTION_TO_SPECIMEN, MIN_ISOLATES, SPECTRUM_ORDER

PNEUMONIA_NOTE = "Pneumonia is not in this data: there are no respiratory samples."


def _specimen(q):
    infection = getattr(q, "infection_type", None)
    return q.specimen or (INFECTION_TO_SPECIMEN[infection] if infection else None)


def _note(q) -> str | None:
    return PNEUMONIA_NOTE if getattr(q, "infection_type", None) == "pneumonia" else None


def _win(q):
    return fx.window_out(q.window, q.as_of, q.date_from, q.date_to)


def _profile(q) -> susc.Filters:
    return susc.Filters(ward=q.ward, specimen=_specimen(q), sex=q.sex, age_band=q.age_band, onset=q.onset)


def _pneumonia(q) -> bool:
    return getattr(q, "infection_type", None) == "pneumonia"


@register(
    "get_organisms",
    "Organism mix (WISCA weights) for a patient profile and window.",
    "/organisms",
    OrganismMixQuery,
    OrganismMixOut,
)
def get_organisms(q: OrganismMixQuery) -> OrganismMixOut:
    specimen = _specimen(q)
    window = _win(q)
    out = OrganismMixOut(window=window, ward=q.ward, specimen=specimen, n_first_isolates=0, note=_note(q), organisms=[])
    if _pneumonia(q):
        return out
    mix = cov.organism_mix(get_store(), q.as_of, window.date_from, window.date_to, _profile(q))
    by_organism: dict[str, list[float]] = {}
    for c in mix.cells:
        share_n = by_organism.setdefault(c.organism, [0.0, 0])
        share_n[0] += c.share
        share_n[1] += c.n
    out.n_first_isolates = mix.n
    out.organisms = [
        OrganismShare(organism=o, share=min(1.0, sh), n=int(n))
        for o, (sh, n) in sorted(by_organism.items(), key=lambda kv: -kv[1][0])
    ]
    if mix.n < MIN_ISOLATES:
        out.note = " ".join(filter(None, [out.note, LEAN_NOTE.format(n=mix.n, w=round(100 * mix.prior_weight))]))
    return out


LEAN_NOTE = (
    "Only {n} first isolates in this window: the mix leans {w}% on the hospital mix of the last 12 months."
)


def _coverage_window(q: CoverageQuery, window: WindowOut) -> CoverageWindowSet:
    result = cov.coverage_set(
        get_store(), q.as_of, window.date_from, window.date_to, _profile(q), SPECTRUM_ORDER[_specimen(q)],
        q.max_regimen_size,
    )
    return CoverageWindowSet(
        window=window,
        n_first_isolates=result.n,
        options=[
            RegimenCoverage(regimen=list(r.regimen), coverage=r.coverage, covers_target=r.covers_target)  # type: ignore[arg-type]
            for r in result.options
        ],
        narrowest_effective=list(result.narrowest) if result.narrowest else None,  # type: ignore[arg-type]
    )


@register(
    "get_coverage",
    "Ranked drugs and combinations with ranges, 4 weeks beside 12 months, and the narrowest effective drug.",
    "/coverage",
    CoverageQuery,
    CoverageOut,
)
def get_coverage(q: CoverageQuery) -> CoverageOut:
    recent, annual = _win(q), fx.window_out("365d", q.as_of, None, None)
    note = _note(q)
    if _pneumonia(q):
        empty = lambda w: CoverageWindowSet(window=w, n_first_isolates=0, options=[], narrowest_effective=None)
        return CoverageOut(ward=q.ward, specimen=_specimen(q), note=note, recent=empty(recent), annual=empty(annual))
    return CoverageOut(
        ward=q.ward, specimen=_specimen(q), note=note,
        recent=_coverage_window(q, recent), annual=_coverage_window(q, annual),
    )


def _filters(q, ward=None) -> susc.Filters:
    return susc.Filters(
        ward=ward if ward is not None else q.ward, specimen=q.specimen, organism=q.organism,
        drug=q.drug, sex=q.sex, age_band=q.age_band, onset=q.onset,
    )


def _rows(cells: list[susc.Cell], keep_empty: bool) -> list[SusceptibilityRow]:
    return [
        SusceptibilityRow(
            ward=c.ward, specimen=c.specimen, organism=c.organism, drug=c.drug,
            counts=SirCounts(s=c.s, i=c.i, r=c.r), resistance=c.estimate, outbreak_inflated=c.outbreak_inflated,
            rate_without_outbreak=c.rate_without_outbreak, note=OUTBREAK_NOTE if c.outbreak_inflated else None,
        )
        for c in cells
        if keep_empty or c.estimate.n > 0
    ]


OUTBREAK_NOTE = (
    "The 12-month rate for this ward is raised by a past outbreak; without those weeks it is lower."
)


@register(
    "get_susceptibility",
    "Resistance rates by organism, drug, ward and window with S, I and R counts, shrunk toward the ward type and hospital.",
    "/susceptibility",
    SusceptibilityQuery,
    SusceptibilityOut,
)
def get_susceptibility(q: SusceptibilityQuery) -> SusceptibilityOut:
    store = get_store()
    f = _filters(q)
    start, end = window_dates(q.as_of, q.window, q.date_from, q.date_to)
    a_start, a_end = window_dates(q.as_of, "365d")
    keep_empty = bool(q.organism and q.drug)  # a ward with no isolates still shows its prior
    recent = susc.estimate_cells(store, q.as_of, start, end, f)
    annual = susc.estimate_cells(store, q.as_of, a_start, a_end, f)
    susc.flag_outbreak_inflation(store, q.as_of, a_end, f, annual)
    return SusceptibilityOut(
        recent=SusceptibilityWindowOut(window=fx.window_out(q.window, q.as_of, q.date_from, q.date_to), rows=_rows(recent, keep_empty)),
        annual=SusceptibilityWindowOut(window=fx.window_out("365d", q.as_of, None, None), rows=_rows(annual, keep_empty)),
    )


@register(
    "get_susceptibility_series",
    "Weekly shrunk resistance series for one organism and drug, per ward against the hospital.",
    "/susceptibility/series",
    SeriesQuery,
    SeriesOut,
)
def get_susceptibility_series(q: SeriesQuery) -> SeriesOut:
    wards = list(dict.fromkeys([*q.wards, *([q.ward] if q.ward else [])]))
    date_to = min(q.date_to or q.as_of, q.as_of)
    date_from = q.date_from or date_to - timedelta(weeks=52)
    days = 365 if q.window == "365d" else 28
    series = susc.weekly_series(get_store(), q.as_of, _filters(q, ward=None), wards, date_from, date_to, days)
    return SeriesOut(
        organism=q.organism, drug=q.drug, as_of=q.as_of,
        series={k: [WeeklyPoint(**p) for p in v] for k, v in series.items()},
    )
