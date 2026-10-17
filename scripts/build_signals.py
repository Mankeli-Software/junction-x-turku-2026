#!/usr/bin/env python
"""Precompute the statistical alert signals for every day of the dataset.

    .venv/bin/python scripts/build_signals.py

Writes backend/app/signals_cache.json. CI runs this before zipping the backend, so the app does
not spend minutes computing the same numbers on the small App Service plan after every deploy.
The file records a fingerprint of the rule constants, the shrinkage code and the data; the app
ignores a file that does not match and computes on demand instead.
"""

import sys
import time
from datetime import timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "backend"))

from app.datalayer import alerts as A
from app.datalayer import signals as sig
from app.datalayer.store import get_store


def main() -> int:
    store = get_store()
    first = A._first_eval_day(store)
    last = store.tables.cultures["sample_date"].max().date()
    days = [first + timedelta(days=i) for i in range((last - first).days + 1)]
    t = time.perf_counter()
    with_hits = sig.build_cache(store, days)
    size = sig.CACHE_FILE.stat().st_size
    print(f"{len(days)} days ({first} to {last}), {with_hits} with a flagged cell, {size / 1024:.0f} KB, {time.perf_counter() - t:.0f}s -> {sig.CACHE_FILE}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
