"""Statistical signals: which ward x organism cells are clearly above the hospital rate on a day.

The rule, applied to the 4-week shrunk ward estimate from susceptibility.py (the same Beta
posterior that backs /v1/susceptibility): a cell fires when the posterior probability that the
ward's rate is above the hospital 12-month rate (plus a margin) is at least CONFIDENCE, and it has
at least MIN_CASES resistant first isolates. Small samples hide percentages, never alerts: a ward
with few isolates fires only if those few are overwhelming against the hospital rate, because the
shrinkage keeps a small sample close to the prior.

Two kinds of rows go through the same maths:
- phenotype: the lab's ESBL and MRSA flags on the isolate, treated as a pseudo-drug (result R when
  flagged). Sharp, because an outbreak shows up in the flag at once. Eligible organisms come from
  the data (any organism that ever carries the flag), not from a list.
- drug: the susceptibility results, one cell per ward x organism x drug, with no margin beyond
  DRUG_MARGIN. One outbreak lights several drugs, so a ward x organism fires only when at least
  MIN_DRUGS drugs are above the hospital rate.
CPE and VRE are sentinel alerts, so they are not repeated here.

Nothing here knows an outbreak date or ward. Results for a day use only data up to that day, so
they are cached per store and reused for any as_of.
"""

import hashlib
import json
import threading
import weakref
from dataclasses import asdict, dataclass
from datetime import date, timedelta
from pathlib import Path

import pandas as pd
from scipy.stats import beta as beta_dist

from app.datalayer import susceptibility as S
from app.datalayer.store import DataStore
from app.vocab import DEFAULT_AS_OF, WARDS

WINDOW_DAYS = 28
CONFIDENCE = 0.99
MIN_CASES = 3
PHENOTYPE_MARGIN = 0.0
DRUG_MARGIN = 0.03  # a 3-point lift is the smallest difference worth an alert
MIN_DRUGS = 2
PHENOTYPE_FLAGS = {"ESBL": "esbl", "MRSA": "mrsa"}
GROUP = ["organism", "drug"]
FILTERS = S.Filters()


@dataclass(frozen=True)
class Hit:
    ward: str
    organism: str
    kind: str  # "phenotype" or "drug"
    name: str  # ESBL / MRSA, or a WHONET drug code
    r: int  # resistant (or flagged) first isolates in the 4-week window
    n: int  # first isolates in the window
    hospital: float  # hospital 12-month rate it is compared with
    rate: float  # shrunk ward rate


def _phenotype_stratum(store: DataStore) -> pd.DataFrame:
    frame = store.isolates(DEFAULT_AS_OF)
    parts = []
    for name, col in PHENOTYPE_FLAGS.items():
        carriers = frame.groupby("organism")[col].sum()
        x = frame[frame["organism"].isin(carriers[carriers > 0].index)].copy()
        x["drug"] = name
        x["result"] = x[col].map({1: "R", 0: "S"})
        parts.append(x)
    return pd.concat(parts, ignore_index=True)


def _drug_stratum(store: DataStore) -> pd.DataFrame:
    return S._stratum(store, FILTERS)


CACHE_FILE = Path(__file__).resolve().parent.parent / "signals_cache.json"  # built in CI, see scripts/build_signals.py
_SOURCES = [Path(__file__), Path(S.__file__), Path(S.__file__).parent.parent / "shrinkage.py"]


def fingerprint(store: DataStore) -> str:
    """Changes whenever the rule, the maths behind it or the data change, so a stale file is never used."""
    c = store.tables.cultures
    parts = {
        "rule": [WINDOW_DAYS, CONFIDENCE, MIN_CASES, PHENOTYPE_MARGIN, DRUG_MARGIN, MIN_DRUGS, sorted(PHENOTYPE_FLAGS)],
        "data": [len(c), len(store.tables.isolates), len(store.tables.susceptibility), str(c["sample_date"].max().date())],
        "code": [hashlib.sha256(f.read_bytes()).hexdigest() for f in _SOURCES],
    }
    return hashlib.sha256(json.dumps(parts, sort_keys=True).encode()).hexdigest()


def build_cache(store: DataStore, days: list[date], path: Path = CACHE_FILE) -> int:
    """Compute the hits for every day and write them with the fingerprint. Returns days with a hit."""
    out = {d.isoformat(): [asdict(h) for h in _compute(store, d)] for d in days}
    path.write_text(json.dumps({"fingerprint": fingerprint(store), "days": out}), encoding="utf-8")
    return sum(1 for v in out.values() if v)


def load_cache(store: DataStore, path: Path = CACHE_FILE) -> dict[date, list[Hit]] | None:
    """The precomputed hits, or None when there is no file or it was built for other code or data."""
    if not path.exists():
        return None
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
        if raw.get("fingerprint") != fingerprint(store):
            return None
        return {date.fromisoformat(d): [Hit(**h) for h in hs] for d, hs in raw["days"].items()}
    except (ValueError, KeyError, TypeError):
        return None


_precomputed: "weakref.WeakKeyDictionary[DataStore, dict[date, list[Hit]] | None]" = weakref.WeakKeyDictionary()


def _from_file(store: DataStore, day: date) -> list[Hit] | None:
    with _lock:
        known = store in _precomputed
    if not known:
        loaded = load_cache(store)
        with _lock:
            _precomputed[store] = loaded
    with _lock:
        cache = _precomputed[store]
    return None if cache is None else cache.get(day)


def cache_status(store: DataStore) -> dict:
    """Whether the precomputed file is in use, and if not, why. Shown by /v1/data-status."""
    if not CACHE_FILE.exists():
        return {"source": "computed on demand", "reason": "no signals_cache.json in the deploy"}
    cache = load_cache(store)
    if cache is None:
        return {"source": "computed on demand", "reason": "signals_cache.json was built for other code or data"}
    return {"source": "precomputed", "days": len(cache)}


class _Strata:
    def __init__(self, store: DataStore):
        self.phenotype = _phenotype_stratum(store)
        self.drug = _drug_stratum(store)


_strata: "weakref.WeakKeyDictionary[DataStore, _Strata]" = weakref.WeakKeyDictionary()
_hits: "weakref.WeakKeyDictionary[DataStore, dict[date, list[Hit]]]" = weakref.WeakKeyDictionary()
_lock = threading.Lock()


def _strata_for(store: DataStore) -> _Strata:
    with _lock:
        if store not in _strata:
            _strata[store] = _Strata(store)
        return _strata[store]


def _evaluate(store: DataStore, day: date, kind: str, stratum: pd.DataFrame, margin: float) -> list[Hit]:
    start, year_start = day - timedelta(days=WINDOW_DAYS - 1), day - timedelta(days=364)
    cells = S.estimate_cells(store, day, start, day, FILTERS, GROUP, wards=list(WARDS), stratum=stratum)
    hospital = {
        (c.organism, c.drug): c.estimate.value
        for c in S.estimate_cells(store, day, year_start, day, FILTERS, GROUP, wards=[None], stratum=stratum)
    }
    out = []
    for c in cells:
        if c.r < MIN_CASES or c.estimate.n == 0:
            continue
        a, b = c.extra["posterior"]
        p_hosp = hospital[(c.organism, c.drug)]
        if beta_dist.sf(p_hosp + margin, a, b) >= CONFIDENCE:
            out.append(Hit(c.ward, c.organism, kind, c.drug, c.r, c.estimate.n, p_hosp, c.estimate.value))
    return out


def _compute(store: DataStore, day: date) -> list[Hit]:
    strata = _strata_for(store)
    phenotype = _evaluate(store, day, "phenotype", strata.phenotype, PHENOTYPE_MARGIN)
    drugs = _evaluate(store, day, "drug", strata.drug, DRUG_MARGIN)
    by_group: dict[tuple[str, str], list[Hit]] = {}
    for h in drugs:
        by_group.setdefault((h.ward, h.organism), []).append(h)
    # one outbreak lights several drugs; a single drug above the hospital rate is not enough
    drugs = [h for hs in by_group.values() if len(hs) >= MIN_DRUGS for h in hs]
    return phenotype + drugs


def hits_on(store: DataStore, day: date) -> list[Hit]:
    """Cells above the hospital rate on `day`, from data up to `day`.

    Read from the precomputed file when it matches this code and data; otherwise computed
    (about 0.2 s on a laptop, several times that on the small App Service plan) and cached.
    """
    with _lock:
        cache = _hits.setdefault(store, {})
        if day in cache:
            return cache[day]
    result = _from_file(store, day)
    if result is None:
        result = _compute(store, day)
    with _lock:
        _hits[store][day] = result
    return result


def warm_up(store: DataStore, first: date, last: date) -> None:
    """Fill the cache for every Sunday in [first, last], newest first (run in a thread at startup)."""
    day = last - timedelta(days=(last.weekday() + 1) % 7)  # latest Sunday on or before last
    while day >= first:
        hits_on(store, day)
        day -= timedelta(days=7)
