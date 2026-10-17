from datetime import date

import pytest
from app.datalayer import alerts as A
from app.datalayer import signals as sig
from app.datalayer import trend as tr
from app.datalayer.store import DataStore, get_store
from app.datalayer.volume import volume, week_start
from app.main import app
from app.models.alerts import AlertsQuery, VolumeQuery
from app.models.common import WindowOut
from fastapi.testclient import TestClient
from helpers import cut_tables

END = date(2026, 9, 27)
client = TestClient(app)
CUT_DATES = (date(2025, 8, 31), date(2025, 12, 31), date(2026, 5, 20))  # after URO, after the PHC-S gap, after ICU


@pytest.fixture(scope="module")
def store():
    """The app's own store, so the API tests and these share one set of computed signals."""
    return get_store()


@pytest.fixture(scope="module")
def cut_stores(store):
    """The data as it was on each date, built once for the leakage tests."""
    return {d: DataStore(cut_tables(store.tables, d)) for d in CUT_DATES}


def _alerts(store, as_of=END, kind=None):
    return [a for a in A.compute_alerts(store, as_of) if kind is None or a.type == kind]


def test_every_cpe_and_vre_isolate_fires(store):
    iso = store.tables.isolates
    flagged = set(iso.loc[(iso["cpe"] == 1) | (iso["vre"] == 1), "isolate_id"])
    assert len(flagged) == 17
    sentinel = _alerts(store, kind="sentinel")
    assert {a.alert_id for a in sentinel} == {f"sentinel-{i}" for i in flagged}
    assert sum(a.phenotype == "CPE" for a in sentinel) == 12
    assert sum(a.phenotype == "VRE" for a in sentinel) == 5
    assert {a.severity for a in sentinel if a.phenotype == "CPE"} == {"critical"}
    assert {a.severity for a in sentinel if a.phenotype == "VRE"} == {"high"}


def test_sentinel_ignores_plain_meropenem_resistance(store):
    """92 of the 104 meropenem-resistant isolates are Pseudomonas: resistance alone must not alert."""
    s = store.tables.susceptibility
    mem_r = set(s.loc[(s["antibiotic_code"] == "MEM") & (s["result"] == "R"), "isolate_id"])
    assert len(mem_r) > 17
    fired = {a.alert_id.removeprefix("sentinel-") for a in _alerts(store, kind="sentinel")}
    assert len(fired) == 17
    assert mem_r - fired  # meropenem-resistant isolates without a CPE flag did not alert


def test_phcs_gap_fires_in_the_following_week(store):
    def gap_alerts(d):
        return [a for a in _alerts(store, d, "missing_data") if a.ward == "PHC-S"]

    assert gap_alerts(date(2025, 12, 13)) == []  # the week is not over yet
    for d in (date(2025, 12, 14), date(2025, 12, 17), date(2025, 12, 21)):
        (a,) = gap_alerts(d)
        assert a.first_seen == date(2025, 12, 8) and a.n_cases == 0
        assert a.verdict == "possible_sampling_artefact" and a.status == "active"
    (a,) = gap_alerts(END)
    assert a.status == "resolved"


def test_no_false_missing_data_alerts(store):
    """Nine wards over three years: the only missing-data alert is the real gap."""
    missing = _alerts(store, kind="missing_data")
    assert [(a.ward, a.first_seen) for a in missing] == [("PHC-S", date(2025, 12, 8))]


def test_alerts_do_not_depend_on_the_future(store, cut_stores):  # sentinel, missing data, statistical, trend
    for as_of, cut in cut_stores.items():
        a, b = A.compute_alerts(store, as_of), A.compute_alerts(cut, as_of)
        assert [x.model_dump() for x in a] == [x.model_dump() for x in b], as_of


def test_detail_does_not_depend_on_the_future(store, cut_stores):
    as_of = date(2025, 12, 31)
    cut = cut_stores[as_of]
    alerts = A.compute_alerts(store, as_of)
    assert {a.type for a in alerts} >= {"sentinel", "missing_data", "statistical", "trend"}
    for alert in alerts:
        assert A.alert_detail(store, alert.alert_id, as_of) == A.alert_detail(cut, alert.alert_id, as_of)


def test_list_filters_and_window(store):
    q = AlertsQuery(as_of=END, window="365d")
    everything = A.list_alerts(store, q).alerts
    recent = A.list_alerts(store, AlertsQuery(as_of=END, window="28d")).alerts
    assert recent == [a for a in everything if (END - a.first_seen).days < 28 or a.status == "active"]
    assert any(a.type == "trend" for a in recent)  # an ongoing trend shows in a short window too
    only_cpe = A.list_alerts(store, AlertsQuery(as_of=END, window="custom", date_from=date(2023, 10, 2), date_to=END, severity="critical"))
    assert len(only_cpe.alerts) == 12
    # a ward filter keeps hospital-wide alerts (ward None): they concern every ward
    assert {a.ward for a in A.list_alerts(store, AlertsQuery(as_of=END, window="365d", ward="PHC-S")).alerts} <= {"PHC-S", None}


def test_sentinel_detail(store):
    d = A.alert_detail(store, "sentinel-C0046602-1", END)
    assert d.alert.ward == "MED-A" and d.alert.phenotype == "CPE"
    assert any(c.sample_date == date(2026, 9, 21) and c.phenotype == "CPE" for c in d.cases)
    assert sum(p.cases for p in d.epi_curve) >= 1
    assert len(d.volume) == len(d.epi_curve) and all(p.cultures > 0 for p in d.volume[:-1])
    assert set(d.ward_comparison) <= {"ED", "MED-A", "MED-B", "SURG", "URO", "ICU", "GER", "PHC-N", "PHC-S"}
    assert d.alert.verdict == "likely_real"


def test_missing_data_detail(store):
    d = A.alert_detail(store, "missing-PHC-S-2025-12-08", date(2025, 12, 21))
    gap = next(p for p in d.epi_curve if p.week_start == date(2025, 12, 8))
    assert gap.cases == 0 and gap.expected > 30
    assert d.ward_comparison["PHC-S"] == 0.0
    assert all(v > 0.5 for w, v in d.ward_comparison.items() if w != "PHC-S")
    assert "specific to the ward" in d.verdict_reason
    assert d.cases == [] and max(p.week_start for p in d.epi_curve) <= date(2025, 12, 15)


def test_unknown_alert_is_404():
    assert client.get("/v1/alerts/detail?alert_id=nope").status_code == 404


def test_volume_counts_every_culture(store):
    window = WindowOut(window="28d", as_of=END, date_from=date(2026, 8, 31), date_to=END)
    out = volume(store, VolumeQuery(as_of=END, window="28d"), window)
    c = store.tables.cultures
    in_win = c[(c["sample_date"] >= "2026-08-31") & (c["sample_date"] <= "2026-09-27")]
    assert sum(r.total for r in out.rows) == len(in_win)
    uro = next(r for r in out.rows if r.ward == "URO" and r.specimen == "urine")
    assert uro.total == len(in_win[(in_win["ward_code"] == "URO") & (in_win["specimen"] == "urine")])
    assert [p.week_start for p in uro.points] == [date(2026, 8, 31), date(2026, 9, 7), date(2026, 9, 14), date(2026, 9, 21)]
    assert all(p.week_start == week_start(p.week_start) for p in uro.points)  # Mondays
    assert uro.baseline_weekly > 0


def test_volume_shows_the_gap(store):
    r = client.get("/v1/volume?ward=PHC-S&as_of=2025-12-21&window=custom&date_from=2025-11-24&date_to=2025-12-21")
    assert r.status_code == 200
    weekly = {}
    for row in r.json()["rows"]:
        for p in row["points"]:
            weekly[p["week_start"]] = weekly.get(p["week_start"], 0) + p["cultures"]
    assert weekly["2025-12-08"] == 0 and weekly["2025-12-01"] > 30


@pytest.mark.parametrize("path", ["/v1/alerts", "/v1/volume"])
def test_routes_validate(path):
    assert client.get(path).status_code == 200


# ---- statistical alerts (ALERT-2) --------------------------------------------------------------


def _stat(store, as_of=END):
    return [a for a in _alerts(store, as_of, "statistical")]


def test_uro_esbl_gives_one_grouped_alert_labelled_likely_real(store):
    uro = [a for a in _stat(store) if a.ward == "URO"]
    assert len(uro) == 1  # one alert per ward x organism, not one per drug
    a = uro[0]
    assert a.organism == "Escherichia coli" and a.phenotype == "ESBL" and a.verdict == "likely_real"
    assert {"CRO", "CXM", "CIP"} <= set(a.drugs)  # the drugs of the outbreak are grouped into it
    assert a.status == "resolved"  # it is over by the end of the data


def test_uro_esbl_is_found_within_two_weeks_of_the_jump(store):
    """ESBL isolates jump in the week of 2025-06-02; the alert is up by 2025-06-15."""
    assert not [a for a in _stat(store, date(2025, 6, 7)) if a.ward == "URO"]
    (a,) = [a for a in _stat(store, date(2025, 6, 15)) if a.ward == "URO"]
    assert a.status == "active" and a.n_cases >= 8
    assert a.first_seen <= date(2025, 6, 2)  # onset is the first case, before the alert fired


def test_alert_identity_and_onset_do_not_move_as_the_date_moves(store):
    ids = {(x.alert_id, x.first_seen) for d in (date(2025, 6, 15), date(2025, 6, 30), date(2025, 7, 20)) for x in _stat(store, d) if x.ward == "URO"}
    assert len(ids) == 1


def test_icu_mrsa_fires_with_fewer_than_thirty_isolates(store):
    (a,) = [a for a in _stat(store) if a.ward == "ICU"]
    assert a.phenotype == "MRSA" and a.organism == "Staphylococcus aureus"
    assert a.first_seen == date(2026, 3, 3)
    assert "13 of 20" in a.summary  # 20 first isolates: small samples hide percentages, never alerts
    assert a.status == "resolved"
    during = _stat(store, date(2026, 3, 22))
    assert any(x.ward == "ICU" and x.status == "active" for x in during)


def test_no_other_statistical_alerts_on_the_full_data(store):
    """Two planted outbreaks, nothing else: no false alarms in nine wards over two years."""
    assert sorted(a.ward for a in _stat(store)) == ["ICU", "URO"]


def test_single_drug_is_not_enough_without_a_phenotype(store):
    """The drug rule needs two drugs above the hospital rate together."""
    for day in (date(2025, 9, 14), date(2026, 2, 8)):  # weeks where one drug was above in some wards
        for h in sig.hits_on(store, day):
            if h.kind == "drug":
                same = [x for x in sig.hits_on(store, day) if x.kind == "drug" and (x.ward, x.organism) == (h.ward, h.organism)]
                assert len(same) >= sig.MIN_DRUGS


def test_statistical_detail(store):
    d = A.alert_detail(store, "stat-URO-escherichia-coli-2025-06-09", END)
    peak = max(d.epi_curve, key=lambda p: p.cases)
    assert peak.cases >= 5 and peak.expected < 1.0  # against the hospital rate for this ward's isolates
    assert len(d.cases) > 20 and all(c.ward == "URO" and c.phenotype == "ESBL" for c in d.cases)
    assert len(d.volume) == len(d.epi_curve)
    assert d.ward_comparison["URO"] == max(d.ward_comparison.values())
    assert "ESBL flag" in d.verdict_reason


def _hit(r, n=20, kind="drug", name="CRO"):
    return sig.Hit("URO", "Escherichia coli", kind, name, r, n, 0.05, 0.3)


def test_labels_use_case_mix_and_volume_together(store, monkeypatch):
    monkeypatch.setattr(A, "_ward_volume_ratio", lambda *a: 1.3)  # volume up, like the real outbreak
    assert A._stat_verdict(store, "URO", [_hit(8), _hit(8, name="CIP")], END)[0] == "likely_real"  # volume rise alone does not dismiss
    assert A._stat_verdict(store, "URO", [_hit(3), _hit(3, name="CIP")], END)[0] == "too_few_cases"
    monkeypatch.setattr(A, "_ward_volume_ratio", lambda *a: 0.4)  # far fewer cultures: selective sampling
    assert A._stat_verdict(store, "URO", [_hit(8), _hit(8, name="CIP")], END)[0] == "possible_sampling_artefact"
    # a lab phenotype flag is not undone by volume
    assert A._stat_verdict(store, "URO", [_hit(8, kind="phenotype", name="ESBL")], END)[0] == "likely_real"


# ---- trend (ALERT-2) ---------------------------------------------------------------------------


def test_trimethoprim_drift_is_detected_and_nothing_else_trends(store):
    found = tr.trends(store, END)
    assert [(t.organism, t.drug) for t in found] == [("Escherichia coli", "TMP")]
    t = found[0]
    assert 1.2 <= t.slope <= 3.1  # the 95% interval from the analysis in #2 (about 2.1 points a year)
    assert t.detected_on <= date(2025, 9, 30)
    (a,) = _alerts(store, END, "trend")
    assert a.ward is None and a.drugs == ["TMP"] and a.verdict == "likely_real"
    assert not _alerts(store, date(2025, 6, 30), "trend")  # too little history before that


def test_trend_detail(store):
    d = A.alert_detail(store, "trend-escherichia-coli-TMP", END)
    assert len(d.epi_curve) == len(d.volume) == 35 and d.cases == []
    assert "Mann-Kendall" in d.verdict_reason
    assert set(d.ward_comparison) <= {"ED", "MED-A", "MED-B", "SURG", "URO", "ICU", "GER", "PHC-N", "PHC-S"}


def test_hospital_wide_alert_validates_over_the_api():
    r = client.get("/v1/alerts?window=365d")
    assert r.status_code == 200
    trend = [a for a in r.json()["alerts"] if a["type"] == "trend"]
    assert trend and trend[0]["ward"] is None
    assert client.get("/v1/alerts/detail?alert_id=trend-escherichia-coli-TMP").status_code == 200


# ---- precomputed signals ----------------------------------------------------------------------


def test_precomputed_signals_equal_computed_ones(store, tmp_path):
    days = [date(2025, 6, 9), date(2025, 6, 10), date(2026, 3, 19)]  # before, at and after the first alerts
    path = tmp_path / "signals_cache.json"
    sig.build_cache(store, days, path)
    loaded = sig.load_cache(store, path)
    assert set(loaded) == set(days)
    for d in days:
        assert loaded[d] == sig._compute(store, d)
    assert loaded[date(2025, 6, 10)] and not loaded[date(2025, 6, 9)]


def test_precomputed_signals_are_ignored_when_stale(store, cut_stores, tmp_path):
    path = tmp_path / "signals_cache.json"
    sig.build_cache(store, [date(2025, 6, 10)], path)
    assert sig.load_cache(store, path) is not None
    assert sig.load_cache(cut_stores[date(2025, 8, 31)], path) is None  # other data: recompute, never reuse
    path.write_text("not json")
    assert sig.load_cache(store, path) is None
    assert sig.load_cache(store, tmp_path / "missing.json") is None


def test_hits_on_prefers_the_file(store, monkeypatch):
    fake = sig.Hit("URO", "Escherichia coli", "phenotype", "ESBL", 9, 30, 0.04, 0.3)
    day = date(2031, 1, 1)  # a day no real computation would ever return a hit for
    monkeypatch.setitem(sig._precomputed, store, {day: [fake]})
    assert sig.hits_on(store, day) == [fake]
    sig._hits[store].pop(day, None)
