from datetime import date, timedelta

import numpy as np
import pandas as pd
import pytest
from app.datalayer import susceptibility as susc
from app.datalayer.store import DataStore, window_dates
from helpers import AS_OF_DATES, cut_tables

URO_ECOLI_CRO = susc.Filters(ward="URO", organism="Escherichia coli", drug="CRO")
ICU_MRSA = susc.Filters(ward="ICU", organism="Staphylococcus aureus", drug="FOX")
PLANTED = {("URO", "Escherichia coli"), ("ICU", "Staphylococcus aureus")}


def series(store, f, start, end):
    out = susc.weekly_series(store, end, f, [f.ward], start, end)
    return {p["week_start"]: p for p in out[f.ward]}, {p["week_start"]: p for p in out["hospital"]}


# --- the estimator ------------------------------------------------------------


def test_no_isolates_rests_on_the_prior():
    e = susc.estimate(0, 0, (30, 300), (50, 500), kappa=12)
    assert e.n == 0 and e.small_sample and e.raw_rate is None
    assert e.value == pytest.approx(0.1, abs=0.01)
    assert e.prior_weight == 1.0
    assert e.prior_level in {"ward_type", "hospital"}


def test_raw_rate_only_from_30_isolates():
    assert susc.estimate(2, 29, (30, 300), (50, 500), 12).raw_rate is None
    assert susc.estimate(3, 30, (30, 300), (50, 500), 12).raw_rate == pytest.approx(0.1)


def test_many_isolates_lean_on_the_ward():
    e = susc.estimate(200, 400, (30, 300), (50, 500), 12)
    assert e.value == pytest.approx(0.5, abs=0.02)
    assert e.prior_level == "ward"
    assert e.low < e.value < e.high


def test_no_jump_at_30_isolates():
    a = susc.estimate(3, 29, (30, 300), (50, 500), 12).value
    b = susc.estimate(3, 30, (30, 300), (50, 500), 12).value
    assert abs(a - b) < 0.01


def test_pooled_rows_lean_on_the_hospital():
    e = susc.estimate(1, 5, None, (50, 500), 20)
    assert e.prior_level == "hospital"
    assert e.value == pytest.approx((1 + 20 * susc.hospital_rate(50, 500)) / 25)


def test_fit_kappa():
    # identical wards: no extra variation, so the guard applies
    assert susc.fit_kappa(np.array([10, 20]), np.array([100, 200])) == susc.KAPPA_MAX
    # wildly different wards: the floor
    assert susc.fit_kappa(np.array([5, 95]), np.array([100, 100])) == susc.KAPPA_MIN
    # one ward cannot be fitted
    assert susc.fit_kappa(np.array([1]), np.array([10])) is None
    # moderate variation lands in between
    k = susc.fit_kappa(np.array([5, 10, 20, 40]), np.array([200, 200, 200, 200]))
    assert susc.KAPPA_MIN < k < susc.KAPPA_MAX


def test_prior_period_covers_long_custom_windows(store):
    assert susc.prior_start(date(2026, 9, 1), date(2026, 9, 28)) == date(2025, 9, 29)
    assert susc.prior_start(date(2024, 1, 1), date(2026, 1, 1)) == date(2024, 1, 1)
    # every cell seen in a two-year window has hospital counts behind it (no 50% fallback)
    as_of = date(2026, 9, 27)
    ctx = susc._context(store, as_of, date(2024, 9, 1), as_of, susc._stratum(store, susc.Filters()), susc.CELL)
    window_keys = set(susc._counts(ctx.win, susc.CELL))
    assert window_keys and window_keys <= set(ctx.ann_hosp)


def test_ward_type_prior_leaves_the_ward_out(store):
    """ED's middle prior is the other outpatient wards (PHC-N, PHC-S), not its own isolates."""
    as_of = date(2026, 9, 27)
    f = susc.Filters(ward="ED", organism="Escherichia coli", drug="CRO", specimen="urine")
    start, end = window_dates(as_of, "28d")
    got = susc.estimate_cells(store, as_of, start, end, f)[0]

    sir = store.sir[(store.sir["organism"] == f.organism) & (store.sir["antibiotic_code"] == f.drug) & (store.sir["specimen"] == "urine")]
    year = sir[sir["isolate_id"].isin(store.first_isolates(as_of, "365d")["isolate_id"])]
    win = sir[sir["isolate_id"].isin(store.first_isolates(as_of, "28d")["isolate_id"]) & (sir["ward_code"] == "ED")]
    per_ward = year.groupby("ward_code")["result"].agg(R=lambda s: (s == "R").sum(), n="size")
    others = per_ward.loc[["PHC-N", "PHC-S"]].sum()
    kappa = susc.fit_kappa(per_ward["R"].to_numpy(), per_ward["n"].to_numpy())
    expected = susc.estimate(
        int((win["result"] == "R").sum()), len(win), (int(others["R"]), int(others["n"])),
        (int((year["result"] == "R").sum()), len(year)), kappa,
    )
    assert got.estimate.value == pytest.approx(expected.value)


# --- trajectories (#1 finding 7, with the fitted prior) ---------------------------------
#
# With the prior fitted from the data the estimate is a calibrated forecast, so the peaks are
# lower than the 38% / 49% in #1 (which came from a hand-set prior). These tests pin the shape
# and the timing: flat before, a clear rise within two weeks, a peak, and a return.


def test_uro_ecoli_ceftriaxone_trajectory(store):
    ward, hospital = series(store, URO_ECOLI_CRO, date(2025, 5, 12), date(2025, 9, 1))
    rate = {w: p["shrunk_rate"] for w, p in ward.items()}
    assert rate[date(2025, 5, 12)] < 0.06  # about 4% before
    # first resistant cluster lands in the week of 2 June; two weeks later the estimate has doubled
    assert rate[date(2025, 6, 16)] > 2 * rate[date(2025, 5, 12)]
    peak_week = max(rate, key=rate.get)
    assert peak_week in {date(2025, 6, 30), date(2025, 7, 7)}
    assert 0.12 < rate[peak_week] < 0.22
    assert rate[date(2025, 8, 25)] < 0.06  # back to normal
    # the hospital rate the ward shrinks toward barely moves
    assert max(p["shrunk_rate"] for p in hospital.values()) < 0.06


def test_icu_mrsa_trajectory(store):
    ward, _ = series(store, ICU_MRSA, date(2026, 2, 16), date(2026, 5, 11))
    rate = {w: p["shrunk_rate"] for w, p in ward.items()}
    assert rate[date(2026, 2, 16)] < 0.05  # about 3% before
    # first MRSA isolates in the week of 2 March; two weeks later the estimate has more than tripled
    assert rate[date(2026, 3, 16)] > 3 * rate[date(2026, 2, 16)]
    peak_week = max(rate, key=rate.get)
    assert peak_week in {date(2026, 3, 23), date(2026, 3, 30)}
    assert 0.18 < rate[peak_week] < 0.35
    assert rate[date(2026, 4, 27)] < 0.05


def test_small_samples_still_move_the_estimate(store):
    """The ICU MRSA cluster was 13 of 20: n is under 30, the raw rate is hidden, the estimate moves."""
    ward, _ = series(store, ICU_MRSA, date(2026, 3, 1), date(2026, 4, 5))
    peak = max(ward.values(), key=lambda p: p["shrunk_rate"])
    assert peak["n"] < susc.MIN_ISOLATES and peak["raw_rate"] is None and peak["shrunk_rate"] > 0.18


def test_series_hospital_line_is_the_12_month_hospital_rate(store):
    week = date(2025, 6, 30)
    _, hospital = series(store, URO_ECOLI_CRO, week, week + timedelta(days=6))
    end = week + timedelta(days=6)
    ids = store.first_isolates(end, "custom", end - timedelta(days=364), end)["isolate_id"]
    sir = store.sir[store.sir["isolate_id"].isin(ids) & (store.sir["organism"] == "Escherichia coli") & (store.sir["antibiotic_code"] == "CRO")]
    r, n = int((sir["result"] == "R").sum()), len(sir)
    point = hospital[week]
    assert (point["r"], point["n"]) == (r, n)
    assert point["shrunk_rate"] == pytest.approx(susc.hospital_rate(r, n))


# --- outbreak inflation flag ------------------------------------------------------


def annual_cells(store, f, as_of):
    annual = susc.estimate_cells(store, as_of, *window_dates(as_of, "365d"), f)
    susc.flag_outbreak_inflation(store, as_of, as_of, f, annual)
    return annual


def flagged(store, f, as_of):
    """By specimen, for filters that pin organism and drug."""
    return {c.specimen: c for c in annual_cells(store, f, as_of)}


def test_flag_after_outbreak_not_before_or_during(store):
    after = flagged(store, URO_ECOLI_CRO, date(2025, 12, 7))["urine"]
    assert after.outbreak_inflated  # months after, the 12-month rate is still about 11%
    assert after.rate_without_outbreak < 0.06 < after.r / (after.s + after.r)
    assert not flagged(store, URO_ECOLI_CRO, date(2025, 3, 2))["urine"].outbreak_inflated  # before
    assert not flagged(store, URO_ECOLI_CRO, date(2025, 7, 20))["urine"].outbreak_inflated  # during: that is an alert


def test_flag_sees_a_cluster_split_across_block_edges(store):
    # the ICU wound cluster falls into two 4-week blocks (4/7 and 3/9 at the end of June)
    assert flagged(store, ICU_MRSA, date(2026, 6, 30))["wound"].outbreak_inflated
    assert flagged(store, ICU_MRSA, date(2026, 9, 27))["wound"].outbreak_inflated


def test_flag_rarely_fires_outside_the_planted_outbreaks(store):
    """Every ward at every quarter end: flags belong to the planted outbreaks, not to noise."""
    planted = outside = 0
    for as_of in [date(2024, 12, 31), date(2025, 3, 31), date(2025, 6, 30), date(2025, 9, 30),
                  date(2025, 12, 31), date(2026, 3, 31), date(2026, 6, 30), date(2026, 9, 27)]:
        for ward in store.tables.wards["ward_code"]:
            for c in annual_cells(store, susc.Filters(ward=ward), as_of):
                if c.outbreak_inflated:
                    if (ward, c.organism) in PLANTED:
                        planted += 1
                    else:
                        outside += 1
    assert planted >= 10
    assert outside <= 0.2 * (planted + outside)


# --- filters and shape ------------------------------------------------------------


def test_pooled_rows_have_no_ward_and_ward_rows_do(store):
    as_of = date(2026, 9, 27)
    pooled = susc.estimate_cells(store, as_of, *window_dates(as_of, "365d"), susc.Filters(organism="Escherichia coli", drug="CRO"))
    assert {c.ward for c in pooled} == {None}
    assert {c.specimen for c in pooled} == {"urine", "blood", "wound"}
    assert {c.estimate.prior_level for c in pooled} == {"hospital"}
    ward = susc.estimate_cells(store, as_of, *window_dates(as_of, "365d"), URO_ECOLI_CRO)
    assert {c.ward for c in ward} == {"URO"}
    assert all(c.s + c.i + c.r == c.estimate.n for c in ward)


def test_demographic_filters_narrow_the_counts(store):
    as_of = date(2026, 9, 27)
    base = susc.Filters(organism="Escherichia coli", drug="TMP", specimen="urine")
    window = window_dates(as_of, "365d")
    all_n = susc.estimate_cells(store, as_of, *window, base)[0].estimate.n
    women = susc.estimate_cells(store, as_of, *window, susc.Filters(**{**base.__dict__, "sex": "F"}))[0].estimate.n
    hosp = susc.estimate_cells(store, as_of, *window, susc.Filters(**{**base.__dict__, "onset": "hospital"}))[0].estimate.n
    assert 0 < women < all_n and 0 < hosp < all_n


# --- as_of ------------------------------------------------------------------------


def snapshot(store, as_of):
    out = {}
    for f in (URO_ECOLI_CRO, ICU_MRSA):
        for name in ("28d", "365d"):
            cells = susc.estimate_cells(store, as_of, *window_dates(as_of, name), f)
            if name == "365d":
                susc.flag_outbreak_inflation(store, as_of, as_of, f, cells)
            out[(f.ward, name)] = sorted(
                (c.specimen, c.organism, c.drug, c.s, c.i, c.r, c.outbreak_inflated, c.estimate.model_dump_json())
                for c in cells
            )
    out["series"] = susc.weekly_series(store, as_of, URO_ECOLI_CRO, ["URO"], as_of - timedelta(weeks=12), as_of)
    return out


@pytest.mark.parametrize("as_of", AS_OF_DATES)
def test_as_of_susceptibility_equals_values_on_cut_data(tables, store, as_of):
    cut = DataStore(cut_tables(tables, as_of))
    assert snapshot(store, as_of) == snapshot(cut, as_of)


def test_series_never_reads_past_as_of(store):
    as_of = date(2025, 6, 18)  # a Wednesday: the last point stops there, not on Sunday
    out = susc.weekly_series(store, as_of, URO_ECOLI_CRO, ["URO"], date(2025, 6, 2), date(2025, 7, 31))
    assert max(p["week_start"] for p in out["URO"]) == pd.Timestamp(as_of).to_period("W").start_time.date()
