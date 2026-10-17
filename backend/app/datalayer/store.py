"""Load the six CSVs, derive columns, and serve as_of-cut views of the data.

Results are cached in memory keyed on as_of. Nothing after as_of is visible in a
view, so replaying an earlier date gives the numbers that date would have shown.
"""

import logging
import threading
import time
from collections import OrderedDict
from collections.abc import Callable
from dataclasses import dataclass
from datetime import date, timedelta
from pathlib import Path

import numpy as np
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

log = logging.getLogger("uvicorn.error")

FIRSTS_CACHE_SIZE = 128
SIR_FILTER_COLUMNS = ("specimen", "organism", "antibiotic_code", "sex", "age_band", "onset")
STRATA_CACHE_SIZE = 256
STRATA_CACHE_MAX_ROWS = 30_000  # keeps the memo to a few tens of MB


@dataclass(frozen=True)
class Tables:
    patients: pd.DataFrame
    cultures: pd.DataFrame
    isolates: pd.DataFrame
    susceptibility: pd.DataFrame
    antibiotics: pd.DataFrame
    wards: pd.DataFrame


TABLE_COLUMNS = {  # the CSV columns, in file order, per table; the order by is the primary key
    "patients": ("patient_id", "sex", "birth_year", "home_area"),
    "cultures": (
        "culture_id", "patient_id", "age_years", "sample_date", "iso_year", "iso_week", "ward_code", "ward_fi",
        "ward_en", "ward_type", "institution", "admission_date", "specimen", "specimen_fi", "result", "n_isolates",
    ),
    "isolates": ("isolate_id", "culture_id", "isolate_no", "organism", "quantity", "esbl", "mrsa", "vre", "cpe"),
    "susceptibility": None,  # all columns
    "antibiotics": None,
    "wards": None,
}
ORDER_BY = {
    "patients": "patient_id", "cultures": "culture_id", "isolates": "isolate_id",
    "susceptibility": "isolate_id, antibiotic_code", "antibiotics": "antibiotic_code", "wards": "ward_code",
}
DATE_COLUMNS = {"cultures": ["sample_date", "admission_date"]}


def _read_csv_tables(d: Path) -> dict[str, pd.DataFrame]:
    return {
        "patients": pd.read_csv(d / "patients.csv"),
        "cultures": pd.read_csv(d / "cultures.csv", parse_dates=["sample_date", "admission_date"]),
        "isolates": pd.read_csv(d / "isolates.csv"),
        "susceptibility": pd.read_csv(d / "susceptibility.csv"),
        "antibiotics": pd.read_csv(d / "antibiotics.csv"),
        "wards": pd.read_csv(d / "wards.csv"),
    }


def _read_postgres_tables() -> dict[str, pd.DataFrame]:
    """The six tables from Postgres, shaped exactly like the CSVs (columns, dtypes, missing as NaN)."""
    from app.db import connect  # imported here so the csv path never needs a database

    out: dict[str, pd.DataFrame] = {}
    with connect(timeout=15) as conn:
        for name, cols in TABLE_COLUMNS.items():
            select = ", ".join(cols) if cols else "*"
            cur = conn.execute(f"SELECT {select} FROM {name} ORDER BY {ORDER_BY[name]}")  # names are constants
            frame = pd.DataFrame(cur.fetchall(), columns=[c.name for c in cur.description])
            for col in DATE_COLUMNS.get(name, []):
                frame[col] = pd.to_datetime(frame[col])
            for col in frame.columns[frame.dtypes == object]:
                frame[col] = frame[col].where(frame[col].notna(), np.nan)  # NULL -> NaN, as read_csv does
            out[name] = frame
    return out


def load_tables(data_dir: str | Path | None = None, check_counts: bool = True, source: str | None = None) -> Tables:
    source = source or settings.data_source
    raw = _read_postgres_tables() if source == "postgres" else _read_csv_tables(Path(data_dir or settings.data_dir))
    for name, cols in DATE_COLUMNS.items():
        for col in cols:  # one resolution whatever the source or pandas version parsed
            raw[name][col] = pd.to_datetime(raw[name][col]).dt.as_unit("ns")
    tables = Tables(**raw)
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
    The dedup is hospital-wide: the isolate counts for the ward where the patient first had
    it in the window (CLSI M39). Over 12 months this counts fewer isolates per ward than
    per-ward dedup would (URO 541 against 612 at the end of the data); at 28 days it makes
    almost no difference.
    """
    in_window = frame[(frame["sample_date"] >= pd.Timestamp(date_from)) & (frame["sample_date"] <= pd.Timestamp(date_to))]
    ordered = in_window.sort_values(["sample_date", "culture_id", "isolate_no"])
    return ordered.drop_duplicates(["patient_id", "organism", "specimen"], keep="first")


class DataStore:
    def __init__(self, tables: Tables):
        self.tables = tables
        self._frame = build_isolate_frame(tables)  # sorted by sample_date
        # The date of the same patient's previous isolate of this organism and specimen (NaT for the
        # first). An isolate is the first in a window exactly when it lies in the window and that
        # date is before the window starts, so a window is two comparisons, not a sort and a dedup:
        # a weekly series needs hundreds of windows.
        self._dates = self._frame["sample_date"].to_numpy()
        self._isolate_index = pd.Index(self._frame["isolate_id"])
        self._prev_dates = (
            self._frame.groupby(["patient_id", "organism", "specimen"], sort=False, dropna=False)["sample_date"]
            .shift(1)
            .to_numpy()
        )
        self._firsts: OrderedDict[tuple, pd.DataFrame] = OrderedDict()
        sir_cols = ["isolate_id", "antibiotic_code", "result"]
        self.sir = self._frame.merge(tables.susceptibility[sir_cols], on="isolate_id", how="inner")
        # Integer codes of the filter columns: comparing 172k small ints is far cheaper than strings.
        self._sir_codes = {c: pd.factorize(self.sir[c]) for c in SIR_FILTER_COLUMNS}
        self._strata: OrderedDict[tuple, pd.DataFrame] = OrderedDict()
        self._strata_lock = threading.Lock()

    def sir_rows(self, **filters: str | None) -> pd.DataFrame:
        """The S/I/R rows matching every given column value (None means no filter), as one slice.

        Small results are remembered, so the 4-week and the 12-month estimate of one request, and
        repeated requests, filter the table once. Treat the result as read-only.
        """
        wanted = {c: v for c, v in filters.items() if v is not None}
        if not wanted:
            return self.sir
        key = tuple(sorted(wanted.items()))
        with self._strata_lock:
            if key in self._strata:
                self._strata.move_to_end(key)
                return self._strata[key]
        mask = None
        for col, val in wanted.items():
            codes, uniques = self._sir_codes[col]
            hit = uniques.get_indexer([val])[0]
            m = codes == hit if hit >= 0 else np.zeros(len(codes), dtype=bool)
            mask = m if mask is None else mask & m
        rows = self.sir[mask]
        if len(rows) <= STRATA_CACHE_MAX_ROWS:
            with self._strata_lock:
                self._strata[key] = rows
                if len(self._strata) > STRATA_CACHE_SIZE:
                    self._strata.popitem(last=False)
        return rows

    def isolates(self, as_of: date) -> pd.DataFrame:
        """All isolates sampled on or before as_of (a slice of the sorted frame, not a copy)."""
        end = self._frame["sample_date"].searchsorted(pd.Timestamp(as_of), side="right")
        return self._frame.iloc[:end]

    def first_isolates(self, as_of: date, window: str = "28d", date_from: date | None = None, date_to: date | None = None) -> pd.DataFrame:
        start, end = window_dates(as_of, window, date_from, date_to)
        key = (as_of, start, end)
        if key in self._firsts:
            self._firsts.move_to_end(key)
        else:
            lo, hi = np.datetime64(pd.Timestamp(start)), np.datetime64(pd.Timestamp(end))
            # end is never past as_of, so nothing later is read; NaT >= lo is False: a first ever
            in_window = (self._dates >= lo) & (self._dates <= hi) & ~(self._prev_dates >= lo)
            self._firsts[key] = self._frame[in_window]  # same rows, order and index as first_isolates()
            if len(self._firsts) > FIRSTS_CACHE_SIZE:
                self._firsts.popitem(last=False)
        return self._firsts[key]

    def first_in_window(self, isolate_ids: pd.Series) -> Callable[[date, date], np.ndarray]:
        """For these isolates (rows of the frame or of sir), a function (start, end) -> which of them
        are first isolates in that window: the same selection as first_isolates, without the lookup
        of ids per window. The caller keeps end on or before as_of."""
        pos = self._isolate_index.get_indexer(isolate_ids)
        dates, prev = self._dates[pos], self._prev_dates[pos]

        def mask(start: date, end: date) -> np.ndarray:
            lo, hi = np.datetime64(pd.Timestamp(start)), np.datetime64(pd.Timestamp(end))
            return (dates >= lo) & (dates <= hi) & ~(prev >= lo)

        return mask

    def susceptibility(self, isolates: pd.DataFrame) -> pd.DataFrame:
        """S/R rows for the given isolates (e.g. a first-isolate selection)."""
        return self.tables.susceptibility[self.tables.susceptibility["isolate_id"].isin(isolates["isolate_id"])]


_store: DataStore | None = None
_store_lock = threading.Lock()


def get_store() -> DataStore:
    """The one store of this process. Requests that arrive while it loads wait for that load,
    instead of each reading the whole dataset again."""
    global _store
    if _store is None:
        with _store_lock:
            if _store is None:
                started = time.perf_counter()
                _store = DataStore(load_tables())
                log.info("dataset loaded from %s in %.1f s", settings.data_source, time.perf_counter() - started)
    return _store
