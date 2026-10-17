from datetime import date

from pydantic import BaseModel, Field

from app.models.common import Estimate, ProfileQuery, WindowOut, WindowQuery
from app.vocab import Drug, Interpretation, Organism, Specimen, Ward


# organisms
class OrganismMixQuery(ProfileQuery):
    pass


class OrganismShare(BaseModel):
    organism: Organism
    share: float = Field(ge=0, le=1, description="WISCA weight")
    n: int


class OrganismMixOut(BaseModel):
    window: WindowOut
    ward: Ward | None
    specimen: Specimen | None
    n_first_isolates: int
    note: str | None = None
    organisms: list[OrganismShare]


# coverage
class CoverageQuery(ProfileQuery):
    max_regimen_size: int = Field(default=2, ge=1, le=2)


class RegimenCoverage(BaseModel):
    regimen: list[Drug]
    coverage: Estimate
    covers_target: bool = Field(description="lower bound of coverage is at least 0.90")


class CoverageWindowSet(BaseModel):
    window: WindowOut
    n_first_isolates: int
    options: list[RegimenCoverage]
    narrowest_effective: list[Drug] | None


class CoverageOut(BaseModel):
    ward: Ward | None
    specimen: Specimen | None
    note: str | None = None
    recent: CoverageWindowSet = Field(description="the requested window, e.g. 28d")
    annual: CoverageWindowSet = Field(description="the last 365d for comparison")


# susceptibility
class SusceptibilityQuery(WindowQuery):
    ward: Ward | None = None
    specimen: Specimen | None = None
    organism: Organism | None = None
    drug: Drug | None = None


class SirCounts(BaseModel):
    s: int
    i: int
    r: int


class SusceptibilityRow(BaseModel):
    ward: Ward | None
    specimen: Specimen
    organism: Organism
    drug: Drug
    counts: SirCounts
    resistance: Estimate


class SusceptibilityWindowOut(BaseModel):
    window: WindowOut
    rows: list[SusceptibilityRow]


class SusceptibilityOut(BaseModel):
    recent: SusceptibilityWindowOut
    annual: SusceptibilityWindowOut


class SeriesQuery(SusceptibilityQuery):
    """Weekly series for one organism and drug over a range."""

    organism: Organism
    drug: Drug
    wards: list[Ward] = Field(default_factory=list)


class WeeklyPoint(BaseModel):
    week_start: date
    n: int
    r: int
    raw_rate: float | None
    shrunk_rate: float
    low: float
    high: float


class SeriesOut(BaseModel):
    organism: Organism
    drug: Drug
    as_of: date
    series: dict[str, list[WeeklyPoint]] = Field(description="by ward; 'hospital' is the prior")


__all__ = ["Interpretation"]
