import os
import random
import shutil
from datetime import date, timedelta
from pathlib import Path

import pandas as pd
import pytest
from app.config import settings
from app.datalayer import derive
from app.datalayer.store import (
    EXPECTED_COUNTS,
    DataStore,
    first_isolates,
    get_store,
    load_tables,
    window_dates,
)
from helpers import AS_OF_DATES, cut_tables


def ts(*days):
    return pd.Series(pd.to_datetime(list(days)))


# --- derived columns ---------------------------------------------------------


@pytest.mark.parametrize(
    "age,band",
    [(0, "0-17"), (17, "0-17"), (18, "18-44"), (44, "18-44"), (45, "45-64"), (64, "45-64"),
     (65, "65-74"), (74, "65-74"), (75, "75+"), (99, "75+")],
)
def test_age_band_edges(age, band):
    assert derive.age_band(pd.Series([age])).iloc[0] == band


def test_onset_rule():
    ward_type = pd.Series(["in", "in", "in", "out", "out"])
    sample = ts("2025-01-03", "2025-01-02", "2025-01-10", "2025-01-03", "2025-01-03")
    admission = pd.Series(pd.to_datetime(["2025-01-01", "2025-01-01", "2025-01-01", None, None]))
    result = derive.onset(ward_type, sample, admission)
    # exactly 2 days: hospital; 1 day: community; 9 days: hospital; outpatients: community
    assert list(result) == ["hospital", "community", "hospital", "community", "community"]


def test_week_start_is_monday():
    # 2025-01-05 is a Sunday, 2025-01-06 a Monday
    ws = derive.week_start(ts("2025-01-05", "2025-01-06", "2025-01-08"))
    assert list(ws.dt.strftime("%Y-%m-%d")) == ["2024-12-30", "2025-01-06", "2025-01-06"]


# --- first isolate and deduplication ----------------------------------------


def frame(rows):
    df = pd.DataFrame(rows, columns=["isolate_id", "culture_id", "isolate_no", "patient_id", "organism", "specimen", "sample_date"])
    df["sample_date"] = pd.to_datetime(df["sample_date"])
    return df


def test_dedup_keeps_earliest_per_patient_organism_specimen():
    f = frame([
        ("i2", "c2", 1, "P1", "E. coli", "urine", "2025-03-05"),
        ("i1", "c1", 1, "P1", "E. coli", "urine", "2025-03-01"),
        ("i3", "c3", 1, "P1", "E. coli", "blood", "2025-03-02"),
        ("i4", "c4", 1, "P1", "S. aureus", "urine", "2025-03-02"),
        ("i5", "c5", 1, "P2", "E. coli", "urine", "2025-03-02"),
    ])
    out = first_isolates(f, date(2025, 3, 1), date(2025, 3, 31))
    assert sorted(out["isolate_id"]) == ["i1", "i3", "i4", "i5"]


def test_dedup_is_within_the_window_not_over_history():
    f = frame([
        ("old", "c1", 1, "P1", "E. coli", "urine", "2025-01-01"),
        ("new", "c2", 1, "P1", "E. coli", "urine", "2025-03-10"),
    ])
    out = first_isolates(f, date(2025, 3, 1), date(2025, 3, 31))
    assert list(out["isolate_id"]) == ["new"]


def test_dedup_breaks_same_day_ties_by_culture_and_isolate_no():
    f = frame([
        ("c1-2", "c1", 2, "P1", "E. coli", "urine", "2025-03-01"),
        ("c1-1", "c1", 1, "P1", "E. coli", "urine", "2025-03-01"),
    ])
    assert list(first_isolates(f, date(2025, 3, 1), date(2025, 3, 1))["isolate_id"]) == ["c1-1"]


def test_window_dates():
    assert window_dates(date(2026, 9, 27), "28d") == (date(2026, 8, 31), date(2026, 9, 27))
    assert window_dates(date(2026, 9, 27), "365d")[0] == date(2025, 9, 28)
    assert window_dates(date(2026, 1, 1), "custom", date(2025, 1, 1), date(2026, 6, 1)) == (date(2025, 1, 1), date(2026, 1, 1))
    with pytest.raises(ValueError):
        window_dates(date(2026, 1, 1), "custom")


# --- the real data ----------------------------------------------------------


def test_row_counts(tables):
    for name, n in EXPECTED_COUNTS.items():
        assert len(getattr(tables, name)) == n


def test_load_rejects_wrong_counts(tmp_path):
    src = Path(settings.data_dir)
    for f in src.glob("*.csv"):
        shutil.copy(f, tmp_path / f.name)
    lines = (tmp_path / "patients.csv").read_text().splitlines()
    (tmp_path / "patients.csv").write_text("\n".join(lines[:-1]) + "\n")
    with pytest.raises(ValueError, match="patients: expected 10000 rows, got 9999"):
        load_tables(tmp_path)


def test_derived_columns_on_real_data(store):
    f = store.isolates(date(2026, 9, 27))
    assert len(f) == EXPECTED_COUNTS["isolates"]
    assert set(f["onset"]) == {"community", "hospital"}
    assert set(f["age_band"]) == {"0-17", "18-44", "45-64", "65-74", "75+"}
    assert f["sex"].notna().all()
    # only inpatient wards can be hospital-onset
    assert set(f[f["onset"] == "hospital"]["ward_type"]) == {"in"}


@pytest.mark.parametrize("as_of", AS_OF_DATES)
@pytest.mark.parametrize("window", ["28d", "365d"])
def test_as_of_values_equal_values_on_cut_data(tables, store, as_of, window):
    """Reusable as_of check: full data cut at as_of == data that never contained the future."""
    cut = DataStore(cut_tables(tables, as_of))
    full_first = store.first_isolates(as_of, window)
    cut_first = cut.first_isolates(as_of, window)
    pd.testing.assert_frame_equal(full_first.reset_index(drop=True), cut_first.reset_index(drop=True))
    cols = ["ward_code", "specimen", "organism"]
    pd.testing.assert_series_equal(
        full_first.groupby(cols).size().sort_index(), cut_first.groupby(cols).size().sort_index()
    )
    pd.testing.assert_frame_equal(
        store.susceptibility(full_first).reset_index(drop=True),
        cut.susceptibility(cut_first).reset_index(drop=True),
    )


def test_view_never_shows_the_future(store):
    as_of = date(2025, 6, 30)
    assert store.isolates(as_of)["sample_date"].max() <= pd.Timestamp(as_of)
    assert store.first_isolates(as_of, "365d")["sample_date"].max() <= pd.Timestamp(as_of)


def test_views_are_cached_per_as_of(store):
    a = store.first_isolates(date(2025, 6, 30), "28d")
    assert store.first_isolates(date(2025, 6, 30), "28d") is a
    assert store.first_isolates(date(2025, 7, 7), "28d") is not a


def test_indexed_filter_matches_a_full_scan():
    """store.sir_rows (integer codes, remembered) must return exactly what string comparisons would."""
    store = get_store()
    cases = [
        {},
        {"specimen": "urine", "organism": "Escherichia coli", "antibiotic_code": "TMP", "sex": "F"},
        {"organism": "Escherichia coli", "age_band": "65+"},
        {"onset": "hospital", "sex": "M"},
        {"organism": "No such bug"},
    ]
    for filters in cases:
        expected = store.sir
        for col, val in filters.items():
            expected = expected[expected[col] == val]
        for _ in range(2):  # the second call is served from the memo
            got = store.sir_rows(**filters)
            assert got.index.equals(expected.index), filters


def test_counts_loop_and_groupby_agree():
    """_counts has a plain-loop path for small frames; it must match the groupby path exactly."""
    from app.datalayer import susceptibility as susc

    store = get_store()
    for keys in (["organism", "antibiotic_code"], ["specimen", "organism", "antibiotic_code", "ward_code"], ["antibiotic_code"]):
        for rows in (store.sir.iloc[:3000], store.sir[store.sir["organism"] == "Escherichia coli"].iloc[:1500]):
            small = susc._counts(rows, keys)
            old, susc.SMALL_FRAME_ROWS = susc.SMALL_FRAME_ROWS, 0
            try:
                big = susc._counts(rows, keys)
            finally:
                susc.SMALL_FRAME_ROWS = old
            assert small == big, keys


@pytest.mark.skipif(not os.environ.get("TEST_DATABASE_URL"), reason="needs a Postgres holding the loaded dataset")
def test_tables_from_postgres_equal_the_csv_tables(monkeypatch):
    """Postgres is the production source: it must hand the data layer exactly what the CSVs do."""
    monkeypatch.setattr(settings, "database_url", os.environ["TEST_DATABASE_URL"])
    from_csv = load_tables(source="csv")
    from_db = load_tables(source="postgres")
    for name in EXPECTED_COUNTS | {"antibiotics": 0, "wards": 0}:
        a, b = getattr(from_csv, name), getattr(from_db, name)
        key = list(a.columns)
        pd.testing.assert_frame_equal(
            a.sort_values(key).reset_index(drop=True), b.sort_values(key).reset_index(drop=True), check_dtype=True, obj=name
        )


def test_concurrent_first_requests_load_the_dataset_once(monkeypatch):
    import threading
    import time

    from app.datalayer import store as store_module

    calls = []

    def slow_load():
        calls.append(1)
        time.sleep(0.2)
        return load_tables(source="csv")

    monkeypatch.setattr(store_module, "_store", None)
    monkeypatch.setattr(store_module, "load_tables", slow_load)
    threads = [threading.Thread(target=store_module.get_store) for _ in range(6)]
    [t.start() for t in threads]
    [t.join() for t in threads]
    assert len(calls) == 1


def test_first_isolates_by_previous_date_match_the_sort_and_dedup():
    """The store picks first isolates by the previous isolate's date; it must equal the plain
    sort-and-dedup of first_isolates() for any window and as_of."""
    store = get_store()
    rng = random.Random(7)
    for _ in range(60):
        as_of = date(2023, 10, 2) + timedelta(days=rng.randint(0, 1091))
        start = as_of - timedelta(days=rng.choice([0, 6, 27, 364, 800]))
        end = as_of - timedelta(days=rng.choice([0, 3, 40]))
        if end < start:
            continue
        fast = store.first_isolates(as_of, "custom", start, end)
        assert fast.equals(first_isolates(store.isolates(as_of), start, end)), (as_of, start, end)
        firsts = store.first_in_window(store.sir["isolate_id"])
        picked = set(store.sir.loc[firsts(start, end), "isolate_id"])
        assert picked == set(fast["isolate_id"]) & set(store.sir["isolate_id"])
