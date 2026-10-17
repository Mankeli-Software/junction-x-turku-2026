"""Postgres access. Kept tiny: the health check and the loader need a connection, nothing more."""

import psycopg

from app.config import settings


def connect(timeout: int = 5) -> psycopg.Connection:
    return psycopg.connect(settings.database_url, connect_timeout=timeout)


def ping() -> bool:
    """True only if the database answers SELECT 1."""
    try:
        with connect() as conn:
            return conn.execute("SELECT 1").fetchone() == (1,)
    except psycopg.Error:
        return False


# Row counts of the dataset CSVs, asserted after every load and on every deploy.
DATASET_ROWS = {
    "wards": 9,
    "antibiotics": 13,
    "patients": 10_000,
    "cultures": 46_792,
    "isolates": 24_571,
    "susceptibility": 172_381,
}


def table_counts() -> dict[str, int]:
    """Actual row count per dataset table. Table names come from DATASET_ROWS, never from input."""
    with connect() as conn:
        return {t: conn.execute(f"SELECT count(*) FROM {t}").fetchone()[0] for t in DATASET_ROWS}
