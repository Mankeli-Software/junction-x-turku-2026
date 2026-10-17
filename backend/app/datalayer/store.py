"""Load the six CSVs, derive columns, and serve as_of-cut views of the data.

Results are cached in memory keyed on as_of. Nothing after as_of is visible in a
view, so replaying an earlier date gives the numbers that date would have shown.
"""

from dataclasses import dataclass
from datetime import date, timedelta
from pathlib import Path

import pandas as pd

from app.config import settings
from app.datalayer import derive
from app.vocab import WINDOW_DAYS

EXPECTED_COUNTS = {
    "patients": 10_000,
    "cultures": 46_792,
    "isolates": 24_571,
    "susceptibility": 172_381,
}


@dataclass(frozen=True)
class Tables:
    patients: pd.DataFrame
    cultures: pd.DataFrame
    isolates: pd.DataFrame
    susceptibility: pd.DataFrame
    antibiotics: pd.DataFrame
    wards: pd.DataFrame


def load_tables(data_dir: str | Path | None = None, check_counts: bool = True) -> Tables:
    d = Path(data_dir or settings.data_dir)
    tables = Tables(
        patients=pd.read_csv(d / "patients.csv"),
        cultures=pd.read_csv(d / "cultures.csv", parse_dates=["sample_date", "admission_date"]),
        isolates=pd.read_csv(d / "isolates.csv"),
        susceptibility=pd.read_csv(d / "susceptibility.csv"),
        antibiotics=pd.read_csv(d / "antibiotics.csv"),
        wards=pd.read_csv(d / "wards.csv"),
    )
    if check_counts:
        for name, expected in EXPECTED_COUNTS.items():
            got = len(getattr(tables, name))
            if got != expected:
                raise ValueError(f"{name}: expected {expected} rows, got {got}")
    return tables


def build_isolate_frame(t: Tables) -> pd.DataFrame:
    """One row per isolate with its culture and patient context and the derived columns."""
    c = t.cultures.copy()
    c["age_band"] = derive.age_band(c["age_years"])
    c["onset"] = derive.onset(c["ward_type"], c["sample_date"], c["admission_date"])
    c["week_start"] = derive.week_start(c["sample_date"])
    c = c.merge(t.patients[["patient_id", "sex"]], on="patient_id", how="left")
    cols = [
        "culture_id", "patient_id", "sample_date", "week_start", "iso_year", "iso_week",
        "ward_code", "ward_type", "institution", "specimen", "sex", "age_years", "age_band", "onset",
    ]
    iso = t.isolates.merge(c[cols], on="culture_id", how="inner")
    return iso.sort_values(["sample_date", "culture_id", "isolate_no"]).reset_index(drop=True)


def window_dates(as_of: date, window: str = "28d", date_from: date | None = None, date_to: date | None = None):
    """Inclusive (from, to) for a named or custom window, never past as_of."""
    if window == "custom":
        if date_from is None or date_to is None:
            raise ValueError("custom window needs date_from and date_to")
        return date_from, min(date_to, as_of)
    return as_of - timedelta(days=WINDOW_DAYS[window] - 1), as_of


def first_isolates(frame: pd.DataFrame, date_from: date, date_to: date) -> pd.DataFrame:
    """First isolate per patient x organism x specimen, deduplicated within the window.

    Deduplicating inside the window (not over all history) keeps a repeat infection
    visible in a 4-week view even if the patient had the same organism earlier.
    """
    in_window = frame[(frame["sample_date"] >= pd.Timestamp(date_from)) & (frame["sample_date"] <= pd.Timestamp(date_to))]
    ordered = in_window.sort_values(["sample_date", "culture_id", "isolate_no"])
    return ordered.drop_duplicates(["patient_id", "organism", "specimen"], keep="first")


class DataStore:
    def __init__(self, tables: Tables):
        self.tables = tables
        self._frame = build_isolate_frame(tables)
        self._views: dict[date, pd.DataFrame] = {}
        self._firsts: dict[tuple, pd.DataFrame] = {}

    def isolates(self, as_of: date) -> pd.DataFrame:
        """All isolates sampled on or before as_of."""
        if as_of not in self._views:
            self._views[as_of] = self._frame[self._frame["sample_date"] <= pd.Timestamp(as_of)]
        return self._views[as_of]

    def first_isolates(self, as_of: date, window: str = "28d", date_from: date | None = None, date_to: date | None = None) -> pd.DataFrame:
        start, end = window_dates(as_of, window, date_from, date_to)
        key = (as_of, start, end)
        if key not in self._firsts:
            self._firsts[key] = first_isolates(self.isolates(as_of), start, end)
        return self._firsts[key]

    def susceptibility(self, isolates: pd.DataFrame) -> pd.DataFrame:
        """S/R rows for the given isolates (e.g. a first-isolate selection)."""
        return self.tables.susceptibility[self.tables.susceptibility["isolate_id"].isin(isolates["isolate_id"])]


_store: DataStore | None = None


def get_store() -> DataStore:
    global _store
    if _store is None:
        _store = DataStore(load_tables())
    return _store
