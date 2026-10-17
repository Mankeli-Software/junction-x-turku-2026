"""Widget catalog: names and parameter JSON Schemas, shared by render_widget and Flutter.

UI person fills this in from the catalog table in #1. Parameters are query
parameters only: widgets fetch their numbers from the API, the AI never writes one.
"""

from typing import Any

from pydantic import BaseModel

from app.models.alerts import AlertDetailQuery, SpreadingQuery, VolumeQuery, WardLinksQuery
from app.models.data import CoverageQuery, OrganismMixQuery, SeriesQuery, SusceptibilityQuery
from app.models.common import ProfileQuery

CATALOG: dict[str, type[BaseModel]] = {
    "ContextChips": ProfileQuery,
    "OrganismMix": OrganismMixQuery,
    "CoverageRanking": CoverageQuery,
    "WindowCompare": SusceptibilityQuery,
    "ResistanceTrend": SeriesQuery,
    "SpreadingCounts": SpreadingQuery,
    "CrossWardWarning": WardLinksQuery,
    "AlertCard": AlertDetailQuery,
    "EpiCurve": AlertDetailQuery,
    "SamplingVolume": VolumeQuery,
}


def catalog_schemas() -> dict[str, dict[str, Any]]:
    return {name: model.model_json_schema() for name, model in CATALOG.items()}
