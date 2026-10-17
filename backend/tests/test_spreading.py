import re
from datetime import date

import pytest
from app.datalayer import spreading as sp
from app.datalayer.store import DataStore, get_store
from app.main import app
from app.models.alerts import SpreadingQuery
from app.models.common import WindowOut
from fastapi.testclient import TestClient
from helpers import cut_tables

END = date(2026, 9, 27)
client = TestClient(app)


@pytest.fixture(scope="module")
def store():
    return get_store()


def _win(q: SpreadingQuery) -> WindowOut:
    from app.datalayer.store import window_dates

    start, end = window_dates(q.as_of, q.window)
    return WindowOut(window=q.window, as_of=q.as_of, date_from=start, date_to=end)


def _spread(store, as_of=END):
    q = SpreadingQuery(as_of=as_of)
    return sp.spreading(store, q, _win(q))


def test_ed_links_match_the_plan(store):
    links = {link.ward: link.shared_patients_30d for link in sp.ward_links(store, "ED", END).links}
    assert (links["PHC-N"], links["GER"], links["URO"]) == (413, 325, 291)


def test_links_are_symmetric(store):
    a = sp.shared_patients(store, "ED", END)
    b = sp.shared_patients(store, "URO", END)
    assert a["URO"] == b["ED"]


def test_ed_is_warned_at_2025_07_01(store):
    links = {link.ward: link for link in sp.ward_links(store, "ED", date(2025, 7, 1)).links}
    uro = links["URO"]
    assert (uro.phenotype, uro.organism) == ("ESBL", "Escherichia coli")
    assert "active ESBL Escherichia coli alert" in uro.warning
    assert links["PHC-N"].phenotype == "CPE"  # the CPE sentinel alert on PHC-N was active too


def test_no_warning_without_an_active_alert(store):
    assert all(link.warning is None for link in sp.ward_links(store, "ED", date(2025, 3, 1)).links)


def test_resolved_alerts_do_not_warn(store):
    # the URO ESBL alert is resolved by March 2026
    links = {link.ward: link for link in sp.ward_links(store, "ED", date(2026, 3, 25)).links}
    assert links["URO"].warning is None


def test_icu_mrsa_is_above_normal(store):
    rows = {(r.ward, r.phenotype): r for r in _spread(store, date(2026, 3, 25)).rows}
    icu = rows[("ICU", "MRSA")]
    assert icu.above_normal and icu.count >= 10 and icu.normal < 1
    assert not rows[("URO", "MRSA")].above_normal


def test_uro_esbl_is_above_normal_at_the_peak(store):
    rows = {(r.ward, r.phenotype): r for r in _spread(store, date(2025, 7, 1)).rows}
    assert rows[("URO", "ESBL")].above_normal


def test_spreading_covers_every_ward_and_flag(store):
    rows = _spread(store).rows
    assert len(rows) == 9 * 4
    q = SpreadingQuery(as_of=END, wards=["ICU"])
    assert {r.ward for r in sp.spreading(store, q, _win(q)).rows} == {"ICU"}


def test_no_baseline_flags_nothing(store):
    assert not any(r.above_normal for r in _spread(store, date(2023, 10, 20)).rows)


@pytest.mark.parametrize("as_of", [date(2025, 7, 1), date(2026, 3, 25)])
def test_nothing_after_as_of_changes_the_result(store, as_of):
    cut = DataStore(cut_tables(store.tables, as_of))
    assert _spread(cut, as_of) == _spread(store, as_of)
    full, early = sp.ward_links(store, "ED", as_of), sp.ward_links(cut, "ED", as_of)
    assert [(link.ward, link.shared_patients_30d) for link in full.links] == [
        (link.ward, link.shared_patients_30d) for link in early.links
    ]


def test_routes_contain_no_patient_ids():
    for url in ("/v1/ward-links?ward=ED&as_of=2025-07-01", "/v1/spreading?as_of=2025-07-01"):
        r = client.get(url)
        assert r.status_code == 200
        assert not re.search(r"P\d{6}", r.text) and "patient_id" not in r.text
