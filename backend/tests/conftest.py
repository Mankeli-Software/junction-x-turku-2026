import pytest
from app.datalayer.store import DataStore, load_tables


@pytest.fixture(scope="session")
def tables():
    return load_tables()  # asserts 10,000 / 46,792 / 24,571 / 172,381


@pytest.fixture(scope="session")
def store(tables):
    return DataStore(tables)
