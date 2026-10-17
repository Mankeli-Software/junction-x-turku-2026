import copy
import time
from datetime import date

import pandas as pd
import pytest
from app.datalayer import coverage as cov
from app.datalayer import susceptibility as susc
from app.datalayer.store import DataStore, window_dates
from app.main import app
from app.vocab import COVERAGE_TARGET, INTRINSIC_RESISTANCE, SPECTRUM_ORDER, URINE_ONLY_DRUGS
from fastapi.testclient import TestClient
from helpers import AS_OF_DATES, cut_tables

AS_OF = date(2026, 9, 27)
DEMO = {"ward": "URO", "infection_type": "uti", "sex": "F", "age_band": "75+", "onset": "hospital"}
DEMO_FILTERS = susc.Filters(ward="URO", specimen="urine", sex="F", age_band="75+", onset="hospital")


@pytest.fixture(scope="module")
def client():
    return TestClient(app)


def run(store, f, as_of=AS_OF, window="28d", specimen="urine", max_size=2):
    start, end = window_dates(as_of, window)
    return cov.coverage_set(store, as_of, start, end, f, SPECTRUM_ORDER[specimen], max_size)


def by_regimen(result):
    return {r.regimen: r for r in result.options}


# --- intrinsic resistance and urine-only drugs --------------------------------


def test_pseudomonas_and_enterococcus_never_covered_by_ceftriaxone(store):
    fake = copy.copy(store)
    sir = store.sir
    # pretend the data had ceftriaxone results for them, all susceptible
    pseudo = sir[sir["organism"] == "Pseudomonas aeruginosa"].copy()
    entero = sir[sir["organism"] == "Enterococcus faecalis"].copy()
    for extra in (pseudo, entero):
        extra["antibiotic_code"] = "CRO"
        extra["result"] = "S"
    fake.sir = pd.concat([sir, pseudo, entero], ignore_index=True)
    start, end = window_dates(AS_OF, "365d")
    rows = cov._covered_rows(fake, AS_OF, start, end, susc.Filters(), SPECTRUM_ORDER[None])
    cro = rows[rows["drug"] == "CRO"]
    assert not cro["organism"].isin(["Pseudomonas aeruginosa", "Enterococcus faecalis"]).any()
    assert (cro["organism"] == "Escherichia coli").any()


def test_intrinsic_pairs_are_absent_from_every_covered_row(store):
    start, end = window_dates(AS_OF, "365d")
    rows = cov._covered_rows(store, AS_OF, start, end, susc.Filters(), SPECTRUM_ORDER[None])
    for organism, drugs in INTRINSIC_RESISTANCE.items():
        assert not rows[(rows["organism"] == organism) & rows["drug"].isin(drugs)].shape[0]


def test_urine_only_drugs_only_for_urine(store):
    start, end = window_dates(AS_OF, "365d")
    rows = cov._covered_rows(store, AS_OF, start, end, susc.Filters(), SPECTRUM_ORDER[None])
    assert (rows[rows["drug"].isin(URINE_ONLY_DRUGS)]["specimen"] == "urine").all()
    blood = run(store, susc.Filters(specimen="blood"), window="365d", specimen="blood")
    assert not {d for r in blood.options for d in r.regimen} & URINE_ONLY_DRUGS
    # without a specimen, blood and wound isolates count as not covered by a urine-only drug
    start, end = window_dates(AS_OF, "365d")
    urine_share = sum(c.share for c in cov.organism_mix(store, AS_OF, start, end, susc.Filters()).cells if c.specimen == "urine")
    mixed = by_regimen(run(store, susc.Filters(), window="365d", specimen=None, max_size=1))
    assert mixed[("NIT",)].coverage.value < urine_share < 1


# --- the demo profile ---------------------------------------------------------


@pytest.mark.parametrize("window", ["28d", "365d"])
def test_demo_profile_narrowest_is_not_meropenem(store, window):
    result = run(store, DEMO_FILTERS, window=window)
    assert result.narrowest is not None
    assert "MEM" not in result.narrowest


def test_narrowest_is_first_in_spectrum_order_that_reaches_the_target(store):
    result = run(store, DEMO_FILTERS, window="365d")
    order = SPECTRUM_ORDER["urine"]
    reaching = [r for r in result.options if r.coverage.low >= COVERAGE_TARGET]
    assert all(r.covers_target for r in reaching)
    singles = [r for r in reaching if len(r.regimen) == 1]
    best = min(reaching, key=lambda r: (len(r.regimen), max(map(order.index, r.regimen)), sum(map(order.index, r.regimen))))
    assert result.narrowest == best.regimen
    assert not singles or len(result.narrowest) == 1


def test_ranges_contain_the_estimate(store):
    for window in ("28d", "365d"):
        for r in run(store, DEMO_FILTERS, window=window).options:
            e = r.coverage
            assert 0 <= e.low <= e.value <= e.high <= 1
            assert e.small_sample == (e.n < 30)
            assert (e.raw_rate is None) == (e.n < 30)


def test_coverage_is_deterministic(store):
    cov.coverage_set.cache_clear()
    a = run(store, DEMO_FILTERS)
    cov.coverage_set.cache_clear()
    b = run(store, DEMO_FILTERS)
    assert [(r.regimen, r.coverage) for r in a.options] == [(r.regimen, r.coverage) for r in b.options]


def test_max_regimen_size_one_gives_single_drugs(store):
    result = run(store, DEMO_FILTERS, max_size=1)
    assert all(len(r.regimen) == 1 for r in result.options)
    assert result.narrowest is None


# --- the organism mix ---------------------------------------------------------


def test_mix_sums_to_one_and_leans_on_the_prior_when_small(store):
    start, end = window_dates(AS_OF, "28d")
    mix = cov.organism_mix(store, AS_OF, start, end, DEMO_FILTERS)
    assert sum(c.share for c in mix.cells) == pytest.approx(1)
    assert mix.n < 30 and mix.prior_weight > 0.4
    assert any(c.n == 0 and c.share > 0 for c in mix.cells)  # unseen organisms keep a prior share


def test_mix_with_many_isolates_follows_the_window(store):
    start, end = window_dates(AS_OF, "365d")
    mix = cov.organism_mix(store, AS_OF, start, end, susc.Filters(specimen="urine"))
    top = max(mix.cells, key=lambda c: c.share)
    assert top.organism == "Escherichia coli"
    assert mix.prior_weight < 0.01


# --- as_of --------------------------------------------------------------------


@pytest.mark.parametrize("as_of", AS_OF_DATES[:3])
def test_nothing_after_as_of_influences_coverage(tables, store, as_of):
    cut = DataStore(cut_tables(tables, as_of))
    for window in ("28d", "365d"):
        full = run(store, DEMO_FILTERS, as_of, window)
        past = run(cut, DEMO_FILTERS, as_of, window)
        assert full.n == past.n and full.narrowest == past.narrowest
        assert [(r.regimen, r.coverage) for r in full.options] == [(r.regimen, r.coverage) for r in past.options]


# --- the routes ---------------------------------------------------------------


def test_coverage_route_demo(client):
    r = client.get("/v1/coverage", params=DEMO)
    assert r.status_code == 200
    body = r.json()
    assert body["specimen"] == "urine"
    for part in ("recent", "annual"):
        assert body[part]["narrowest_effective"] and "MEM" not in body[part]["narrowest_effective"]
    assert body["recent"]["window"]["window"] == "28d" and body["annual"]["window"]["window"] == "365d"


def test_pneumonia_is_not_in_this_data(client):
    for path in ("/v1/coverage", "/v1/organisms"):
        body = client.get(path, params={"infection_type": "pneumonia"}).json()
        assert "not in this data" in body["note"]
    assert client.get("/v1/organisms", params={"infection_type": "pneumonia"}).json()["organisms"] == []
    cov_body = client.get("/v1/coverage", params={"infection_type": "pneumonia"}).json()
    assert cov_body["recent"]["options"] == [] and cov_body["recent"]["narrowest_effective"] is None


def test_organisms_route_shares(client):
    body = client.get("/v1/organisms", params=DEMO).json()
    assert sum(o["share"] for o in body["organisms"]) == pytest.approx(1)
    assert body["organisms"] == sorted(body["organisms"], key=lambda o: -o["share"])
    assert body["note"] and "leans" in body["note"]  # a handful of isolates in 28 days


def test_warm_call_under_200_ms(client):
    client.get("/v1/coverage", params=DEMO)
    started = time.perf_counter()
    client.get("/v1/coverage", params=DEMO)
    assert time.perf_counter() - started < 0.2
