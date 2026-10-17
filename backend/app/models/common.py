from datetime import date
from typing import Literal

from pydantic import BaseModel, Field, model_validator

from app.vocab import DEFAULT_AS_OF, AgeBand, InfectionType, Onset, Sex, Specimen, Ward, Window

PriorLevel = Literal["ward", "ward_type", "hospital"]


class WindowQuery(BaseModel):
    """Every query takes as_of; the window is named or custom."""

    as_of: date = DEFAULT_AS_OF
    window: Window = "28d"
    date_from: date | None = None
    date_to: date | None = None

    @model_validator(mode="after")
    def _custom_needs_dates(self):
        if self.window == "custom" and not (self.date_from and self.date_to):
            raise ValueError("window=custom needs date_from and date_to")
        if self.date_from and self.date_to and self.date_from > self.date_to:
            raise ValueError("date_from must not be after date_to")
        return self


class ProfileQuery(WindowQuery):
    """The described patient: the quick-patient inputs."""

    ward: Ward | None = None
    infection_type: InfectionType | None = None
    specimen: Specimen | None = None
    sex: Sex | None = None
    age_band: AgeBand | None = None
    onset: Onset | None = None


class WindowOut(BaseModel):
    window: str
    as_of: date
    date_from: date
    date_to: date


class Estimate(BaseModel):
    """A shrunk rate with its range and how much it leans on the prior."""

    value: float = Field(ge=0, le=1)
    low: float = Field(ge=0, le=1)
    high: float = Field(ge=0, le=1)
    n: int = Field(ge=0, description="first isolates behind the number")
    prior_level: PriorLevel
    prior_weight: float = Field(ge=0, le=1, description="share of the estimate from the prior")
    small_sample: bool = Field(description="n below the minimum: show the range, not a percentage")
    raw_rate: float | None = Field(None, description="unshrunk rate, given only when n is at least the minimum")
