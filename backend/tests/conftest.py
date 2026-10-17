import pytest
from app.datalayer.store import DataStore, load_tables


@pytest.fixture(scope="session")
def tables():
    return load_tables()  # asserts 10,000 / 46,792 / 24,571 / 172,381


@pytest.fixture(scope="session")
def store(tables):
    return DataStore(tables)


@pytest.fixture(autouse=True)
def memory_dashboards(monkeypatch):
    """Route tests never touch Postgres; the real store has its own test below."""
    from app import dashboard_store

    monkeypatch.setattr(dashboard_store, "store", dashboard_store.MemoryDashboardStore())
