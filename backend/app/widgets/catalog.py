"""Widget catalog: names and parameter JSON Schemas, shared by render_widget and Flutter.

UI person fills this in from the catalog table in #1. Parameters are query
parameters only: widgets fetch their numbers from the API, the AI never writes one.
"""

from datetime import date
from typing import Any, Literal

from pydantic import BaseModel, Field

from app.models.alerts import (
    AlertDetailQuery,
    AlertsQuery,
    SpreadingQuery,
    VolumeQuery,
    WardLinksQuery,
)
from app.models.common import ProfileQuery
from app.models.data import CoverageQuery, OrganismMixQuery, SeriesQuery, SusceptibilityQuery
from app.vocab import DEFAULT_AS_OF, Drug, Organism, Phenotype

# Widget-only params: display filters applied in the app to the same numbers, and the fixed
# notices the AI can pick. None of them carries a number.


class CoverageRankingParams(CoverageQuery):
    oral_only: bool = Field(False, description="display filter: hide drugs with no oral form")
    exclude: list[Drug] = Field(
        default_factory=list, description="display filter: hide these drugs, e.g. penicillins for an allergy"
    )


class SpreadingParams(SpreadingQuery):
    phenotype: Phenotype | None = Field(None, description="display filter: one resistant type")


class CrossWardParams(WardLinksQuery):
    organism: Organism | None = None
    phenotype: Phenotype | None = None


class PatientHistoryParams(BaseModel):
    patient_id: str
    as_of: date = DEFAULT_AS_OF


class NotInThisDataParams(BaseModel):
    topic: str = Field(description="what is missing, e.g. pneumonia")


class OutsideScopeParams(BaseModel):
    reason: Literal["dosing", "identity", "off_topic"]


class ExplainParams(BaseModel):
    topic: Literal["esbl", "mrsa", "sir", "calculation"]


CATALOG: dict[str, type[BaseModel]] = {
    # For the patient in front of you
    "ContextChips": ProfileQuery,
    "CoverageRanking": CoverageRankingParams,
    "OrganismMix": OrganismMixQuery,
    "WindowCompare": SusceptibilityQuery,
    "AlertBanner": AlertsQuery,
    "PatientHistory": PatientHistoryParams,
    # Wards, the lab and research
    "SpreadingCounts": SpreadingParams,
    "CrossWardWarning": CrossWardParams,
    "WardStatus": SpreadingQuery,
    "AlertCard": AlertDetailQuery,
    "EpiCurve": AlertDetailQuery,
    "SamplingVolume": VolumeQuery,
    "CaseList": AlertDetailQuery,
    "ResistanceTrend": SeriesQuery,
    # Limits and explanations
    "NotInThisData": NotInThisDataParams,
    "OutsideScope": OutsideScopeParams,
    "Explain": ExplainParams,
}


def catalog_schemas() -> dict[str, dict[str, Any]]:
    return {name: model.model_json_schema() for name, model in CATALOG.items()}
