"""Organism mix and drug coverage for a patient profile (WISCA).

Mix: first isolates of the profile in the window, per specimen x organism, shrunk toward the
hospital mix of the prior period (Dirichlet-multinomial, prior strength MIX_PRIOR_STRENGTH).

Coverage of a regimen: sum over cells of mix share x P(susceptible | cell, regimen), where
P(susceptible) is one minus the shrunk resistance of susceptibility.py. A regimen that was not
tested on a cell, an intrinsically resistant pair, and a urine-only drug on a non-urine sample
count as not covered. A pair of drugs covers an isolate when either drug does; it is estimated
from isolate-level results as a pseudo-drug, so co-resistance is kept.

Pairs are only built when no single drug reaches the target, and only as the best single drug
plus each other drug: all pairs would cost seconds for the unfiltered profile.

Range: Monte Carlo over the Beta posterior of every cell and the Dirichlet posterior of the
mix, 95% central interval, fixed seed so a request always gives the same numbers.
"""

from dataclasses import dataclass
from datetime import date
from functools import lru_cache

import numpy as np
import pandas as pd

from app.datalayer import susceptibility as susc
from app.datalayer.store import DataStore
from app.models.common import Estimate
from app.vocab import COVERAGE_TARGET, INTRINSIC_RESISTANCE, MIN_ISOLATES, URINE_ONLY_DRUGS

MIX_PRIOR_STRENGTH = 20.0  # first isolates worth of the hospital mix
DRAWS = 1000
SEED = 20260927
MAX_PAIR_OPTIONS = 5
LOW_Q, HIGH_Q = 2.5, 97.5

Regimen = tuple[str, ...]
CellKey = tuple[str, str]  # specimen, organism


@dataclass
class MixCell:
    specimen: str
    organism: str
    n: int
    share: float


@dataclass
class Mix:
    n: int
    cells: list[MixCell]
    prior_weight: float


@dataclass
class RegimenResult:
    regimen: Regimen
    coverage: Estimate
    covers_target: bool


@dataclass
class CoverageSet:
    n: int
    options: list[RegimenResult]
    narrowest: Regimen | None


def _profile(d: pd.DataFrame, f: susc.Filters) -> pd.DataFrame:
    for col, val in [("specimen", f.specimen), ("sex", f.sex), ("age_band", f.age_band), ("onset", f.onset)]:
        if val is not None:
            d = d[d[col] == val]
    return d


def _cell_counts(d: pd.DataFrame) -> dict[CellKey, int]:
    return {k: int(v) for k, v in d.groupby(["specimen", "organism"]).size().items()}


def organism_mix(store: DataStore, as_of: date, start: date, end: date, f: susc.Filters) -> Mix:
    """Window mix of the profile (ward included) shrunk toward the hospital mix of the prior period."""
    win = _profile(store.first_isolates(as_of, "custom", start, end), f)
    if f.ward:
        win = win[win["ward_code"] == f.ward]
    prior = _profile(store.first_isolates(as_of, "custom", susc.prior_start(start, end), end), f)
    n_win, n_prior = _cell_counts(win), _cell_counts(prior)
    keys = sorted(set(n_win) | set(n_prior))
    if not keys:
        return Mix(0, [], 1.0)
    total, total_prior = sum(n_win.values()), sum(n_prior.values())
    k = MIX_PRIOR_STRENGTH
    cells = []
    for key in keys:
        p_hosp = (n_prior.get(key, 0) + 0.5) / (total_prior + 0.5 * len(keys))
        share = (n_win.get(key, 0) + k * p_hosp) / (total + k)
        cells.append(MixCell(key[0], key[1], n_win.get(key, 0), share))
    return Mix(total, cells, k / (total + k))


def _rank(order: tuple[str, ...], regimen: Regimen) -> tuple[int, int, int]:
    ranks = [order.index(d) for d in regimen]
    return len(regimen), max(ranks), sum(ranks)


def _covered_rows(
    store: DataStore, as_of: date, start: date, end: date, f: susc.Filters, drugs: tuple[str, ...],
) -> pd.DataFrame:
    """S/I/R rows of the profile for the offered drugs, minus pairs that count as not covered."""
    ids = store.first_isolates(as_of, "custom", susc.prior_start(start, end), end)["isolate_id"]
    d = store.sir[store.sir["isolate_id"].isin(ids) & store.sir["antibiotic_code"].isin(drugs)]
    d = _profile(d, f).rename(columns={"antibiotic_code": "drug"})
    bad = d["drug"].isin(URINE_ONLY_DRUGS) & (d["specimen"] != "urine")
    for organism, intrinsic in INTRINSIC_RESISTANCE.items():
        bad |= (d["organism"] == organism) & d["drug"].isin(intrinsic)
    return d[~bad]


def _with_pairs(rows: pd.DataFrame, pairs: list[Regimen]) -> pd.DataFrame:
    """Add one pseudo-drug 'A+B' per pair: S when either drug is S, tested when either was tested."""
    if not pairs:
        return rows
    wide = rows.assign(s=rows["result"] == "S").pivot(index="isolate_id", columns="drug", values="s")
    meta = rows.drop_duplicates("isolate_id").set_index("isolate_id").drop(columns=["drug", "result"])
    parts = [rows]
    for a, b in pairs:
        wa = wide[a] if a in wide else pd.Series(np.nan, index=wide.index)
        wb = wide[b] if b in wide else pd.Series(np.nan, index=wide.index)
        tested = wa.notna() | wb.notna()
        covered = (wa == True) | (wb == True)
        part = meta.loc[tested[tested].index].reset_index()
        part["drug"] = f"{a}+{b}"
        part["result"] = np.where(covered[tested].to_numpy(), "S", "R")
        parts.append(part)
    return pd.concat(parts, ignore_index=True)


def _regimen_key(regimen: Regimen) -> str:
    return "+".join(regimen)


def _evaluate(
    mix: Mix, cells: dict[tuple, susc.Cell], regimens: list[Regimen], order: tuple[str, ...], n_isolates: int,
) -> list[RegimenResult]:
    rng = np.random.default_rng(SEED)
    alpha = np.array([max(c.n, 0) + 0.0 for c in mix.cells]) + MIX_PRIOR_STRENGTH * np.array([c.share for c in mix.cells])
    alpha = np.maximum(alpha, 1e-6)
    weights = rng.dirichlet(alpha, size=DRAWS)  # D x C
    share = np.array([c.share for c in mix.cells])
    results = []
    for regimen in regimens:
        key = _regimen_key(regimen)
        found = [cells.get((c.specimen, c.organism, key)) for c in mix.cells]
        a = np.array([f.extra["posterior"][1] if f else 1.0 for f in found])  # Beta of susceptibility
        b = np.array([f.extra["posterior"][0] if f else 1.0 for f in found])
        has = np.array([f is not None for f in found])
        q = rng.beta(a, b, size=(DRAWS, len(found))) * has
        draws = (weights * q).sum(axis=1)
        point_q = np.array([1 - f.estimate.value if f else 0.0 for f in found])
        value = float((share * point_q).sum())
        low, high = (float(x) for x in np.percentile(draws, [LOW_Q, HIGH_Q]))
        low, high = min(low, value), max(high, value)
        w_data = share * has
        pw_cells = float((w_data * np.array([f.estimate.prior_weight if f else 0.0 for f in found])).sum() / w_data.sum()) if w_data.sum() else 1.0
        prior_weight = 1 - (1 - mix.prior_weight) * (1 - pw_cells)
        top = max(range(len(found)), key=lambda i: share[i] * has[i])
        level = found[top].estimate.prior_level if found[top] else "hospital"
        covered_isolates = sum(f.s + f.i for f in found if f)
        est = Estimate(
            value=value, low=low, high=high, n=n_isolates, prior_level=level,  # type: ignore[arg-type]
            prior_weight=round(prior_weight, 4), small_sample=n_isolates < MIN_ISOLATES,
            raw_rate=covered_isolates / n_isolates if n_isolates >= MIN_ISOLATES else None,
        )
        results.append(RegimenResult(regimen, est, low >= COVERAGE_TARGET))
    results.sort(key=lambda r: _rank(order, r.regimen))
    return results


@lru_cache(maxsize=256)
def coverage_set(
    store: DataStore, as_of: date, start: date, end: date, f: susc.Filters, order: tuple[str, ...], max_size: int = 2,
) -> CoverageSet:
    """Coverage of every offered drug, of pairs when no single drug reaches the target, and the narrowest."""
    mix = organism_mix(store, as_of, start, end, f)
    if not mix.cells:
        return CoverageSet(0, [], None)
    rows = _covered_rows(store, as_of, start, end, f, order)

    def estimate(stratum: pd.DataFrame) -> dict[tuple, susc.Cell]:
        found = susc.estimate_cells(store, as_of, start, end, f, stratum=stratum, all_keys=True)
        return {(c.specimen, c.organism, c.drug): c for c in found}

    cells = estimate(rows)
    singles = _evaluate(mix, cells, [(d,) for d in order], order, mix.n)
    options = list(singles)
    effective = [r for r in options if r.covers_target]
    if not effective and max_size >= 2:
        anchor = max(singles, key=lambda r: r.coverage.value).regimen[0]
        pairs = [tuple(sorted((anchor, d), key=order.index)) for d in order if d != anchor]
        cells |= estimate(_with_pairs(rows, pairs))
        evaluated = _evaluate(mix, cells, pairs, order, mix.n)
        effective = [r for r in evaluated if r.covers_target]
        best = sorted(evaluated, key=lambda r: -r.coverage.value)[:MAX_PAIR_OPTIONS]
        options += effective + [r for r in best if r not in effective]
    options.sort(key=lambda r: -r.coverage.value)
    narrowest = min(effective, key=lambda r: _rank(order, r.regimen)).regimen if effective else None
    return CoverageSet(mix.n, options, narrowest)
