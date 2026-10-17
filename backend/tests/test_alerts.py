from datetime import date

import pytest
from app.datalayer import alerts as A
from app.datalayer.store import DataStore
from app.datalayer.volume import volume, week_start
from app.main import app
from app.models.alerts import AlertsQuery, VolumeQuery
from app.models.common import WindowOut
from fastapi.testclient import TestClient
from helpers import AS_OF_DATES, cut_tables

END = date(2026, 9, 27)
client = TestClient(app)


def _alerts(store, as_of=END, kind=None):
    return [a for a in A.compute_alerts(store, as_of) if kind is None or a.type == kind]


def test_every_cpe_and_vre_isolate_fires(store, tables):
    iso = tables.isolates
    flagged = set(iso.loc[(iso["cpe"] == 1) | (iso["vre"] == 1), "isolate_id"])
    assert len(flagged) == 17
    sentinel = _alerts(store, kind="sentinel")
    assert {a.alert_id for a in sentinel} == {f"sentinel-{i}" for i in flagged}
    assert sum(a.phenotype == "CPE" for a in sentinel) == 12
    assert sum(a.phenotype == "VRE" for a in sentinel) == 5
    assert {a.severity for a in sentinel if a.phenotype == "CPE"} == {"critical"}
    assert {a.severity for a in sentinel if a.phenotype == "VRE"} == {"high"}


def test_sentinel_ignores_plain_meropenem_resistance(store, tables):
    """92 of the 104 meropenem-resistant isolates are Pseudomonas: resistance alone must not alert."""
    s = tables.susceptibility
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


def test_alerts_do_not_depend_on_the_future(tables):
    full = DataStore(tables)
    for as_of in AS_OF_DATES:
        cut = DataStore(cut_tables(tables, as_of))
        a, b = A.compute_alerts(full, as_of), A.compute_alerts(cut, as_of)
        assert [x.model_dump() for x in a] == [x.model_dump() for x in b], as_of


def test_detail_does_not_depend_on_the_future(tables):
    full = DataStore(tables)
    as_of = date(2025, 12, 31)
    cut = DataStore(cut_tables(tables, as_of))
    for alert in A.compute_alerts(full, as_of):
        assert A.alert_detail(full, alert.alert_id, as_of) == A.alert_detail(cut, alert.alert_id, as_of)


def test_list_filters_and_window(store):
    q = AlertsQuery(as_of=END, window="365d")
    everything = A.list_alerts(store, q).alerts
    assert A.list_alerts(store, AlertsQuery(as_of=END, window="28d")).alerts == [
        a for a in everything if (END - a.first_seen).days < 28
    ]
    only_cpe = A.list_alerts(store, AlertsQuery(as_of=END, window="custom", date_from=date(2023, 10, 2), date_to=END, severity="critical"))
    assert len(only_cpe.alerts) == 12
    assert {a.ward for a in A.list_alerts(store, AlertsQuery(as_of=END, window="365d", ward="PHC-S")).alerts} == {"PHC-S"}


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


def test_volume_counts_every_culture(store, tables):
    window = WindowOut(window="28d", as_of=END, date_from=date(2026, 8, 31), date_to=END)
    out = volume(store, VolumeQuery(as_of=END, window="28d"), window)
    c = tables.cultures
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
