from datetime import date

from pydantic import BaseModel, Field

from app.models.common import Estimate, ProfileQuery, WindowOut, WindowQuery
from app.vocab import AgeBand, Drug, Interpretation, Onset, Organism, Sex, Specimen, Ward


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
    sex: Sex | None = None
    age_band: AgeBand | None = None
    onset: Onset | None = None


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
    outbreak_inflated: bool = Field(False, description="12-month ward rate is lifted by a past outbreak")
    rate_without_outbreak: float | None = Field(None, description="12-month raw rate without the outbreak weeks")
    note: str | None = None


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
    series: dict[str, list[WeeklyPoint]] = Field(
        description="by ward; 'hospital' is the 12-month hospital rate at the top of the prior chain"
    )


__all__ = ["Interpretation"]
