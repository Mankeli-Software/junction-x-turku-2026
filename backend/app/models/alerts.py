from datetime import date
from typing import Literal

from pydantic import BaseModel, Field

from app.models.common import WindowOut, WindowQuery
from app.vocab import Drug, Organism, Phenotype, Specimen, Ward

AlertType = Literal["sentinel", "statistical", "trend", "missing_data"]
Severity = Literal["low", "medium", "high", "critical"]
AlertStatus = Literal["active", "acknowledged", "resolved"]
Verdict = Literal["likely_real", "possible_sampling_artefact", "too_few_cases"]


class AlertsQuery(WindowQuery):
    ward: Ward | None = None
    severity: Severity | None = None
    status: AlertStatus | None = None


class Alert(BaseModel):
    alert_id: str
    type: AlertType
    severity: Severity
    status: AlertStatus
    ward: Ward | None = Field(None, description="None for a hospital-wide alert (a trend)")
    organism: Organism | None = None
    phenotype: Phenotype | None = None
    drugs: list[Drug] = Field(default_factory=list, description="one outbreak groups its drugs")
    first_seen: date
    as_of: date
    n_cases: int
    summary: str
    verdict: Verdict


class AlertsOut(BaseModel):
    as_of: date
    alerts: list[Alert]


class AlertDetailQuery(WindowQuery):
    alert_id: str


class EpiPoint(BaseModel):
    week_start: date
    cases: int
    expected: float


class CaseRow(BaseModel):
    """Aggregate-safe case row: no patient identifiers."""

    sample_date: date
    ward: Ward
    specimen: Specimen
    organism: Organism
    phenotype: Phenotype | None = None


class VolumePoint(BaseModel):
    week_start: date
    cultures: int


class AlertDetailOut(BaseModel):
    alert: Alert
    epi_curve: list[EpiPoint]
    cases: list[CaseRow]
    volume: list[VolumePoint]
    ward_comparison: dict[str, float] = Field(description="case rate by ward")
    verdict_reason: str


class VolumeQuery(WindowQuery):
    ward: Ward | None = None
    specimen: Specimen | None = None


class VolumeRow(BaseModel):
    ward: Ward
    specimen: Specimen
    points: list[VolumePoint]
    total: int
    baseline_weekly: float


class VolumeOut(BaseModel):
    window: WindowOut
    rows: list[VolumeRow]


class SpreadingQuery(WindowQuery):
    wards: list[Ward] = Field(default_factory=list)


class SpreadingRow(BaseModel):
    ward: Ward
    phenotype: Phenotype
    count: int
    normal: float = Field(description="typical count for the same window length")
    above_normal: bool


class SpreadingOut(BaseModel):
    window: WindowOut
    rows: list[SpreadingRow]


class WardLinksQuery(WindowQuery):
    ward: Ward


class WardLink(BaseModel):
    ward: Ward
    shared_patients_30d: int
    warning: str | None = Field(None, description="aggregate only, no patient data")
    organism: Organism | None = None
    phenotype: Phenotype | None = None


class WardLinksOut(BaseModel):
    ward: Ward
    as_of: date
    links: list[WardLink]
