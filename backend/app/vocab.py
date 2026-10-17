"""Shared vocabulary: the values every model, route and widget agrees on."""

from datetime import date
from typing import Literal

DEFAULT_AS_OF = date(2026, 9, 27)

Ward = Literal["ED", "MED-A", "MED-B", "SURG", "URO", "ICU", "GER", "PHC-N", "PHC-S"]
WARDS: tuple[str, ...] = Ward.__args__  # type: ignore[attr-defined]

Specimen = Literal["urine", "blood", "wound"]
SPECIMENS: tuple[str, ...] = Specimen.__args__  # type: ignore[attr-defined]

Organism = Literal[
    "Escherichia coli",
    "Staphylococcus aureus",
    "Enterococcus faecalis",
    "Klebsiella pneumoniae",
    "Proteus mirabilis",
    "Pseudomonas aeruginosa",
    "Citrobacter freundii",
    "Klebsiella oxytoca",
    "Staphylococcus saprophyticus",
]
ORGANISMS: tuple[str, ...] = Organism.__args__  # type: ignore[attr-defined]

# WHONET codes, as in antibiotics.csv
Drug = Literal["AMP", "MEC", "TZP", "FOX", "CXM", "CRO", "CAZ", "MEM", "CIP", "TMP", "NIT", "VAN", "CLI"]
DRUGS: tuple[str, ...] = Drug.__args__  # type: ignore[attr-defined]

Sex = Literal["F", "M"]
AgeBand = Literal["0-17", "18-44", "45-64", "65-74", "75+"]
AGE_BANDS: tuple[str, ...] = AgeBand.__args__  # type: ignore[attr-defined]

Onset = Literal["community", "hospital"]
# Hospital onset: inpatient and sample_date - admission_date >= ONSET_MIN_DAYS.
ONSET_MIN_DAYS = 2

# Rolling windows: named, or "custom" with explicit from/to dates.
Window = Literal["28d", "365d", "custom"]
WINDOW_DAYS: dict[str, int] = {"28d": 28, "365d": 365}

# EUCAST categories; the dataset has only S and R, the schema carries I.
Interpretation = Literal["S", "I", "R"]

InfectionType = Literal["uti", "sepsis", "wound", "pneumonia"]
# Pneumonia maps to no specimen: respiratory samples are not in the data.
INFECTION_TO_SPECIMEN: dict[str, str | None] = {
    "uti": "urine",
    "sepsis": "blood",
    "wound": "wound",
    "pneumonia": None,
}

Phenotype = Literal["ESBL", "MRSA", "VRE", "CPE"]

# Minimum first isolates before a percentage is shown (alerts are never hidden).
MIN_ISOLATES = 30
