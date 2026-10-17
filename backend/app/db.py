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
