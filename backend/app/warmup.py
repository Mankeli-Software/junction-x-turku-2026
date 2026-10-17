"""Fill the caches before the first user arrives.

The data never changes, so every answer a screen asks for at its default can be computed once, right
after the process starts. This runs the same registry functions the REST routes call, so the answers
land in the result cache (`registry._remembered`) and in the alert caches.

With `gunicorn --preload` it runs once in the master process, before the workers fork, and both
workers inherit the finished caches. A time budget stops it from holding up the container start.
The list below is what the screens send at their defaults; anything outside it is computed on first use.
"""

import logging
import time
from datetime import date, timedelta

from fastapi import HTTPException
from pydantic import ValidationError

from app.config import settings
from app.registry import REGISTRY
from app.vocab import WARDS

log = logging.getLogger("uvicorn.error")

INFECTION_TYPES = ("uti", "sepsis", "wound")  # pneumonia has no data and is answered without a query
DOCTOR_WINDOWS = ("28d", "365d")  # the last 4 weeks beside the last 12 months
result: dict | None = None  # what the last run did; shown by /v1/data-status
RESEARCH_DEFAULT = {"specimen": "urine", "organism": "Escherichia coli", "drug": "TMP"}


def _research_periods(as_of: date) -> list[tuple[date, date]]:
    """The 12-month periods the Research page compares, oldest first; the oldest starts at the data start."""
    first = date(2023, 10, 2)
    periods, end = [], as_of
    while end >= first:
        periods.append((max(end - timedelta(days=364), first), end))
        end = end - timedelta(days=365)
    return list(reversed(periods))


def queries(as_of: date) -> list[tuple[str, dict]]:
    """(function name, parameters) in the order they matter: the first screens first."""
    q: list[tuple[str, dict]] = []
    # Home, infection control and the lab inbox
    q += [("get_alerts", {}), ("get_spreading", {}), ("get_spreading_series", {}), ("get_volume", {})]
    q += [("get_ward_links", {"ward": w}) for w in WARDS]
    q += [("get_susceptibility", {"ward": w}) for w in WARDS]
    # The doctor flow: organism mix and coverage for each ward and infection type
    for window in DOCTOR_WINDOWS:
        for w in WARDS:
            for t in INFECTION_TYPES:
                q.append(("get_organisms", {"ward": w, "infection_type": t, "window": window}))
                q.append(("get_coverage", {"ward": w, "infection_type": t, "window": window}))
    # Research at its defaults: three periods, split by sex and unsplit, plus the trend line
    for start, end in _research_periods(as_of):
        window = {"window": "custom", "date_from": start.isoformat(), "date_to": end.isoformat()}
        q.append(("get_susceptibility", {**RESEARCH_DEFAULT, **window}))
        q += [("get_susceptibility", {**RESEARCH_DEFAULT, **window, "sex": s}) for s in ("F", "M")]
    q.append(("get_susceptibility_series", {**RESEARCH_DEFAULT, "window": "365d", "wards": ["URO", "ICU"]}))
    return q


def run(budget_seconds: float | None = None) -> dict:
    """Load the dataset, build the alert caches, then run the screen queries until the budget is spent."""
    from app.datalayer import alerts as alert_engine
    from app.datalayer.store import get_store

    budget = settings.warm_budget_seconds if budget_seconds is None else budget_seconds
    started = time.perf_counter()
    store = get_store()
    alert_engine.warm_up(store)
    as_of = settings.as_of_default
    done = failed = 0
    plan = queries(as_of)
    for name, params in plan:
        if time.perf_counter() - started > budget:
            log.warning("warm-up stopped at its %.0f s budget after %d of %d queries", budget, done, len(plan))
            break
        fn = REGISTRY[name]
        try:
            fn.handler(fn.input_model(**{"as_of": as_of.isoformat(), **params}))
            done += 1
        except (ValidationError, ValueError) as e:
            failed += 1
            log.warning("warm-up query %s %s failed: %s", name, params, type(e).__name__)
    # The alert detail pages of the alerts a user sees first.
    for alert in REGISTRY["get_alerts"].handler(REGISTRY["get_alerts"].input_model(as_of=as_of.isoformat())).alerts[:20]:
        if time.perf_counter() - started > budget:
            break
        fn = REGISTRY["get_alert_detail"]
        try:
            fn.handler(fn.input_model(as_of=as_of.isoformat(), alert_id=alert.alert_id))
            done += 1
        except (HTTPException, ValidationError, ValueError) as e:  # a missing detail must not stop the start
            failed += 1
            log.warning("warm-up alert detail %s failed: %s", alert.alert_id, type(e).__name__)
    seconds = time.perf_counter() - started
    log.info("warm-up done: %d queries (%d failed) in %.1f s", done, failed, seconds)
    global result
    result = {"queries": done, "failed": failed, "seconds": round(seconds, 1)}
    return result
