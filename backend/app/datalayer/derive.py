"""Derived columns: age band, onset and ISO week start."""

import pandas as pd

from app.vocab import ONSET_MIN_DAYS

# Upper bounds (inclusive) of each band, in the order of vocab.AGE_BANDS.
_AGE_EDGES = [-1, 17, 44, 64, 74, 200]
_AGE_LABELS = ["0-17", "18-44", "45-64", "65-74", "75+"]


def age_band(age_years: pd.Series) -> pd.Series:
    return pd.cut(age_years, bins=_AGE_EDGES, labels=_AGE_LABELS).astype("object")


def onset(ward_type: pd.Series, sample_date: pd.Series, admission_date: pd.Series) -> pd.Series:
    """'hospital' for an inpatient sampled at least ONSET_MIN_DAYS after admission, else 'community'."""
    days = (sample_date - admission_date).dt.days
    hospital = (ward_type == "in") & (days >= ONSET_MIN_DAYS)
    return pd.Series(["hospital" if h else "community" for h in hospital], index=sample_date.index)


def week_start(sample_date: pd.Series) -> pd.Series:
    """Monday of the ISO week."""
    return sample_date - pd.to_timedelta(sample_date.dt.weekday, unit="D")
