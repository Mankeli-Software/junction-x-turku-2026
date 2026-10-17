import os
import uuid

import pytest
from app import dashboard_store
from app.main import app
from app.models.dashboard import DashboardOut, WidgetPlacement
from fastapi.testclient import TestClient

client = TestClient(app)


class Down:
    def get(self, user_id):
        raise dashboard_store.StoreUnavailable("down")

    def put(self, out):
        raise dashboard_store.StoreUnavailable("down")


def test_read_falls_back_to_default_when_db_is_down(monkeypatch):
    monkeypatch.setattr(dashboard_store, "store", Down())
    r = client.get("/v1/dashboard?user_id=x")
    assert r.status_code == 200 and r.json()["role"] == "doctor"


def test_save_fails_loudly_when_db_is_down(monkeypatch):
    monkeypatch.setattr(dashboard_store, "store", Down())
    body = {"user_id": "x", "role": "lab", "layout": []}
    assert client.put("/v1/dashboard", json=body).status_code == 503


@pytest.mark.skipif("TEST_DATABASE_URL" not in os.environ, reason="needs a Postgres with schema.sql")
def test_postgres_store_roundtrip(monkeypatch):
    monkeypatch.setattr(dashboard_store.db.settings, "database_url", os.environ["TEST_DATABASE_URL"])
    store = dashboard_store.PostgresDashboardStore()
    uid = f"test-{uuid.uuid4()}"
    first = DashboardOut(user_id=uid, role="lab", layout=[WidgetPlacement(widget="AlertCard")])
    second = DashboardOut(
        user_id=uid, role="hygiene", layout=[WidgetPlacement(widget="OrganismMix", params={"ward": "ICU"})]
    )
    try:
        assert store.get(uid) is None
        store.put(first)
        assert store.get(uid) == first
        store.put(second)  # upsert
        assert store.get(uid) == second
    finally:
        with dashboard_store.db.connect() as conn:
            conn.execute("DELETE FROM user_dashboards WHERE user_id = %s", (uid,))
