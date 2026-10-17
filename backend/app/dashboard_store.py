"""Where saved dashboards live: the user_dashboards table, or memory in tests."""

import logging
from typing import Protocol

import psycopg
from psycopg.types.json import Jsonb

from app import db
from app.models.dashboard import DashboardOut, WidgetPlacement

log = logging.getLogger(__name__)


class StoreUnavailable(Exception):
    """The database could not be reached or answered with an error."""


class DashboardStore(Protocol):
    def get(self, user_id: str) -> DashboardOut | None: ...
    def put(self, out: DashboardOut) -> None: ...
    def delete(self, user_id: str) -> None: ...


class PostgresDashboardStore:
    def get(self, user_id: str) -> DashboardOut | None:
        try:
            with db.connect() as conn:
                row = conn.execute(
                    "SELECT role, layout FROM user_dashboards WHERE user_id = %s", (user_id,)
                ).fetchone()
        except psycopg.Error as e:
            raise StoreUnavailable(str(e)) from e
        if row is None:
            return None
        role, layout = row
        return DashboardOut(user_id=user_id, role=role, layout=[WidgetPlacement(**w) for w in layout])

    def put(self, out: DashboardOut) -> None:
        layout = Jsonb([w.model_dump() for w in out.layout])
        try:
            with db.connect() as conn:
                conn.execute(
                    """
                    INSERT INTO user_dashboards (user_id, role, layout, updated_at)
                    VALUES (%s, %s, %s, now())
                    ON CONFLICT (user_id) DO UPDATE
                    SET role = EXCLUDED.role, layout = EXCLUDED.layout, updated_at = now()
                    """,
                    (out.user_id, out.role, layout),
                )
        except psycopg.Error as e:
            raise StoreUnavailable(str(e)) from e

    def delete(self, user_id: str) -> None:
        try:
            with db.connect() as conn:
                conn.execute("DELETE FROM user_dashboards WHERE user_id = %s", (user_id,))
        except psycopg.Error as e:
            raise StoreUnavailable(str(e)) from e


class MemoryDashboardStore:
    def __init__(self) -> None:
        self._saved: dict[str, DashboardOut] = {}

    def get(self, user_id: str) -> DashboardOut | None:
        return self._saved.get(user_id)

    def put(self, out: DashboardOut) -> None:
        self._saved[out.user_id] = out

    def delete(self, user_id: str) -> None:
        self._saved.pop(user_id, None)


store: DashboardStore = PostgresDashboardStore()
