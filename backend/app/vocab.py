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

# Drugs the data reports for urine samples only (antibiotics.csv reported_for).
URINE_ONLY_DRUGS: frozenset[str] = frozenset({"MEC", "TMP", "NIT"})

# Intrinsic resistance after EUCAST Expected Resistant Phenotypes v1.2, limited to the drugs in
# the data. Such a pair is never covered, whatever the isolates in the data show.
_GRAM_NEGATIVE_NEVER = {"VAN", "CLI"}
INTRINSIC_RESISTANCE: dict[str, frozenset[str]] = {
    "Escherichia coli": frozenset(_GRAM_NEGATIVE_NEVER),
    "Klebsiella pneumoniae": frozenset({"AMP", *_GRAM_NEGATIVE_NEVER}),
    "Klebsiella oxytoca": frozenset({"AMP", *_GRAM_NEGATIVE_NEVER}),
    "Citrobacter freundii": frozenset({"AMP", "CXM", "FOX", *_GRAM_NEGATIVE_NEVER}),
    "Proteus mirabilis": frozenset({"NIT", *_GRAM_NEGATIVE_NEVER}),
    "Pseudomonas aeruginosa": frozenset(
        {"AMP", "MEC", "CXM", "CRO", "FOX", "TMP", "NIT", *_GRAM_NEGATIVE_NEVER}
    ),
    "Enterococcus faecalis": frozenset({"MEC", "CXM", "CRO", "CAZ", "FOX", "CLI"}),
    "Staphylococcus aureus": frozenset({"MEC", "CAZ"}),
    "Staphylococcus saprophyticus": frozenset({"MEC", "CAZ"}),
}

# Spectrum order, narrowest first: the narrowest drug that covers is picked first. Drugs not
# listed (the FOX screen; AMP, CAZ, CLI and VAN for urine) are not offered for that specimen.
URINE_SPECTRUM = ("NIT", "MEC", "TMP", "CXM", "CIP", "CRO", "TZP", "MEM")
SYSTEMIC_SPECTRUM = ("AMP", "CLI", "CXM", "CIP", "CRO", "CAZ", "TZP", "MEM", "VAN")
MIXED_SPECTRUM = ("NIT", "MEC", "TMP", "AMP", "CLI", "CXM", "CIP", "CRO", "CAZ", "TZP", "MEM", "VAN")
SPECTRUM_ORDER: dict[str | None, tuple[str, ...]] = {
    "urine": URINE_SPECTRUM,
    "blood": SYSTEMIC_SPECTRUM,
    "wound": SYSTEMIC_SPECTRUM,
    None: MIXED_SPECTRUM,
}

# Coverage target: the lower bound of the range must reach it.
COVERAGE_TARGET = 0.90
