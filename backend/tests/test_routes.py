import pytest
from app import db
from app.main import REGISTRY, app
from fastapi.testclient import TestClient

client = TestClient(app)

SAMPLES = {
    "get_organisms": "?ward=URO&infection_type=uti",
    "get_coverage": "?ward=URO&infection_type=uti&sex=F&age_band=75%2B&onset=hospital",
    "get_susceptibility": "?organism=Escherichia%20coli&drug=CRO",
    "get_susceptibility_series": "?organism=Escherichia%20coli&drug=CRO&wards=URO&wards=ICU",
    "get_alerts": "",
    "get_alert_detail": "?alert_id=sentinel-C0046602-1",
    "get_volume": "?ward=URO",
    "get_spreading": "?wards=ICU",
    "get_ward_links": "?ward=URO",
    "get_dashboard": "",
}


@pytest.mark.parametrize("name", SAMPLES)
def test_get_route_serves_valid_fixture(name):
    fn = REGISTRY[name]
    r = client.get(f"/v1{fn.path}{SAMPLES[name]}")
    assert r.status_code == 200, r.text
    fn.output_model.model_validate(r.json())


def test_every_function_is_covered():
    assert set(REGISTRY) - set(SAMPLES) == {"put_dashboard"}


def test_put_dashboard_roundtrip():
    body = {"user_id": "u1", "role": "lab", "layout": [{"widget": "AlertCard", "params": {}}]}
    assert client.put("/v1/dashboard", json=body).status_code == 200
    assert client.get("/v1/dashboard?user_id=u1").json()["role"] == "lab"


def test_pneumonia_is_honest():
    r = client.get("/v1/coverage?infection_type=pneumonia")
    assert "not in this data" in r.json()["note"]


def test_bad_ward_rejected():
    assert client.get("/v1/coverage?ward=XYZ").status_code == 422


def test_custom_window_needs_dates():
    assert client.get("/v1/coverage?window=custom").status_code == 422


def test_healthz_follows_the_database(monkeypatch):
    monkeypatch.setattr("app.main.db.ping", lambda: True)
    assert client.get("/healthz").json() == {"status": "ok"}
    monkeypatch.setattr("app.main.db.ping", lambda: False)
    assert client.get("/healthz").status_code == 503


def test_data_status_reports_mismatches(monkeypatch):
    good = dict(db.DATASET_ROWS)
    monkeypatch.setattr("app.main.db.table_counts", lambda: good)
    assert client.get("/v1/data-status").json()["ok"] is True
    monkeypatch.setattr("app.main.db.table_counts", lambda: {**good, "patients": 9_999})
    body = client.get("/v1/data-status").json()
    assert body["ok"] is False and body["tables"]["patients"]["actual"] == 9_999


def test_cors():
    r = client.options(
        "/v1/alerts",
        headers={"Origin": "http://localhost:3000", "Access-Control-Request-Method": "GET"},
    )
    assert r.headers["access-control-allow-origin"] == "http://localhost:3000"


def test_window_is_clipped_to_as_of():
    r = client.get("/v1/susceptibility?ward=URO&window=custom&date_from=2026-09-01&date_to=2026-12-31&as_of=2026-09-27")
    assert r.status_code == 200
    assert r.json()["recent"]["window"]["date_to"] == "2026-09-27"


def test_reversed_dates_rejected():
    assert client.get("/v1/susceptibility?window=custom&date_from=2026-02-01&date_to=2026-01-01").status_code == 422


def test_outbreak_flag_reaches_the_api():
    r = client.get("/v1/susceptibility?ward=URO&organism=Escherichia%20coli&drug=CRO&specimen=urine&as_of=2025-12-07")
    row = r.json()["annual"]["rows"][0]
    assert row["outbreak_inflated"] and row["note"]
    assert row["rate_without_outbreak"] < row["counts"]["r"] / (row["counts"]["s"] + row["counts"]["r"])
