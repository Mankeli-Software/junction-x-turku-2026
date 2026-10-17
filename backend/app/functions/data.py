from app.fixtures import data as fx
from app.models.data import (
    CoverageOut,
    CoverageQuery,
    OrganismMixOut,
    OrganismMixQuery,
    SeriesOut,
    SeriesQuery,
    SusceptibilityOut,
    SusceptibilityQuery,
)
from app.registry import register
from app.vocab import INFECTION_TO_SPECIMEN

PNEUMONIA_NOTE = "Pneumonia is not in this data: there are no respiratory samples."


def _specimen(q):
    infection = getattr(q, "infection_type", None)
    return q.specimen or (INFECTION_TO_SPECIMEN[infection] if infection else None)


def _note(q) -> str | None:
    return PNEUMONIA_NOTE if getattr(q, "infection_type", None) == "pneumonia" else None


def _win(q):
    return fx.window_out(q.window, q.as_of, q.date_from, q.date_to)


@register(
    "get_organisms",
    "Organism mix (WISCA weights) for a patient profile and window.",
    "/organisms",
    OrganismMixQuery,
    OrganismMixOut,
)
def get_organisms(q: OrganismMixQuery) -> OrganismMixOut:
    out = fx.organism_mix(q.as_of, _win(q), q.ward, _specimen(q))
    out.note = _note(q)
    return out


@register(
    "get_coverage",
    "Ranked drugs and combinations with ranges, 4 weeks beside 12 months, and the narrowest effective drug.",
    "/coverage",
    CoverageQuery,
    CoverageOut,
)
def get_coverage(q: CoverageQuery) -> CoverageOut:
    annual = fx.window_out("365d", q.as_of, None, None)
    out = fx.coverage(_win(q), annual, q.ward, _specimen(q))
    out.note = _note(q)
    return out


@register(
    "get_susceptibility",
    "Resistance rates by organism, drug, ward and window with S, I and R counts.",
    "/susceptibility",
    SusceptibilityQuery,
    SusceptibilityOut,
)
def get_susceptibility(q: SusceptibilityQuery) -> SusceptibilityOut:
    annual = fx.window_out("365d", q.as_of, None, None)
    return fx.susceptibility(_win(q), annual, q.ward, q.specimen, q.organism, q.drug)


@register(
    "get_susceptibility_series",
    "Weekly shrunk resistance series for one organism and drug, per ward against the hospital.",
    "/susceptibility/series",
    SeriesQuery,
    SeriesOut,
)
def get_susceptibility_series(q: SeriesQuery) -> SeriesOut:
    return fx.weekly_series(q.as_of, q.organism, q.drug, list(q.wards))
