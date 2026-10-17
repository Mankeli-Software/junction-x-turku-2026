"""Susceptibility estimates with shrinkage along the chain ward -> ward type -> hospital.

Counting: first isolates only, deduplicated within each window across the whole hospital. An
isolate counts for the ward where the patient first had that organism in that specimen type
during the window (the CLSI M39 convention; per-ward dedup would count a patient once on every
ward they were sampled on). Resistance is R / (S + I + R) among isolates tested for the drug.
Untested drugs are not counted here; coverage (DATA-3) handles intrinsic resistance.

Estimate: each level is a Beta prior for the one below it.
  hospital rate   p_h = (R_h + 0.5) / (N_h + 1)               the whole hospital
  ward type rate  p_t = (R_t + k p_h) / (N_t + k)             the other wards of the same type (in / out)
  ward rate       p_w = (R_w + k p_t) / (N_w + k)             <- (R + a) / (n + a + b), a = k p_t
The prior period is the 12 months ending at the window end, or the whole window if it is longer.
k is the prior strength, fitted per specimen x organism x drug from how much the wards varied in
the prior period (beta-binomial method of moments). It is not tuned to any known signal: the
estimate is a calibrated forecast, and spotting outbreaks is the alerts module's job.
"""

from dataclasses import dataclass, field
from datetime import date, timedelta
from statistics import median

import numpy as np
import pandas as pd
from scipy.stats import beta as beta_dist
from scipy.stats import hypergeom

from app.datalayer.store import DataStore
from app.models.common import Estimate
from app.shrinkage import shrunk_rate
from app.vocab import MIN_ISOLATES

# Guards, not tuning. With no extra variation between wards the fit is unbounded; the ceiling
# keeps a ward's range from collapsing onto the prior. The fallback is used only when no cell in
# the request has two wards to fit from.
KAPPA_MIN, KAPPA_MAX, KAPPA_FALLBACK = 1.0, 200.0, 20.0
CREDIBLE = 0.95

# Outbreak inflation of the 12-month ward rate, set from general practice, not from the data.
BLOCK_DAYS = 28
N_BLOCKS = 365 // BLOCK_DAYS + 1  # block 0 is the latest 4 weeks
MAX_RUN_BLOCKS = 3  # an outbreak period lasts up to 12 weeks
FAMILY_ALPHA = 0.01  # chance per cell and year of calling noise an outbreak
MIN_EXCESS = 0.03  # 12-month rate at least 3 points above the year without the elevated blocks

CELL = ["specimen", "organism", "drug"]

Counts = tuple[int, int, int, int]  # S, I, R, n


@dataclass(frozen=True)
class Filters:
    ward: str | None = None
    specimen: str | None = None
    organism: str | None = None
    drug: str | None = None
    sex: str | None = None
    age_band: str | None = None
    onset: str | None = None


@dataclass
class Cell:
    ward: str | None
    specimen: str | None
    organism: str
    drug: str
    s: int
    i: int
    r: int
    estimate: Estimate
    outbreak_inflated: bool = False
    rate_without_outbreak: float | None = None
    extra: dict = field(default_factory=dict)


@dataclass
class _Context:
    """Window counts and prior-period counts for one request."""

    group_cols: list[str]
    win: pd.DataFrame
    ann_ward: dict[tuple, Counts]
    ann_type: dict[tuple, Counts]
    ann_hosp: dict[tuple, Counts]
    kappa: dict[tuple, float]
    kappa_fallback: float


def prior_start(start: date, end: date) -> date:
    """The prior period: 12 months ending at the window end, or the whole window if longer."""
    return min(start, end - timedelta(days=364))


def _stratum(store: DataStore, f: Filters) -> pd.DataFrame:
    """All S/I/R rows for the non-ward filters."""
    d = store.sir_rows(specimen=f.specimen, organism=f.organism, antibiotic_code=f.drug,
                       sex=f.sex, age_band=f.age_band, onset=f.onset)
    return d.rename(columns={"antibiotic_code": "drug"})


SMALL_FRAME_ROWS = 4000


def _counts(rows: pd.DataFrame, keys: list[str]) -> dict[tuple, Counts]:
    if rows.empty:
        return {}
    if len(rows) <= SMALL_FRAME_ROWS:
        # A groupby/unstack costs about a millisecond of fixed pandas overhead; the weekly series
        # makes hundreds of calls on a few hundred rows, where a plain loop is several times faster.
        rows = rows.dropna(subset=keys)  # NaN keys are dropped, as groupby does
        tally: dict[tuple, list[int]] = {}
        slot = {"S": 0, "I": 1, "R": 2}
        for *key, result in zip(*(rows[c].to_numpy() for c in (*keys, "result")), strict=True):
            tally.setdefault(tuple(key), [0, 0, 0])[slot[result]] += 1
        one = len(keys) == 1  # groupby keys a single column by its value, not a 1-tuple
        return {(k[0] if one else k): (v[0], v[1], v[2], v[0] + v[1] + v[2]) for k, v in tally.items()}
    c = rows.groupby([*keys, "result"]).size().unstack(fill_value=0).reindex(columns=["S", "I", "R"], fill_value=0)
    s, i, r = c["S"].to_numpy(), c["I"].to_numpy(), c["R"].to_numpy()
    return {k: (int(a), int(b), int(x), int(a + b + x)) for k, a, b, x in zip(c.index, s, i, r)}


def fit_kappa(r: np.ndarray, n: np.ndarray) -> float | None:
    """Prior strength from between-ward variation (beta-binomial method of moments).

    None when fewer than two wards have data.
    """
    keep = n > 0
    r, n = r[keep], n[keep]
    w = len(n)
    if w < 2:
        return None
    total = n.sum()
    p = r.sum() / total
    if p <= 0 or p >= 1:
        return KAPPA_MAX
    nbar = total / w
    s2 = (n * (r / n - p) ** 2).sum() / ((w - 1) * nbar)
    rho = (s2 - p * (1 - p) / nbar) / (p * (1 - p) * (1 - 1 / nbar))
    if rho <= 0:
        return KAPPA_MAX
    return float(np.clip(1 / rho - 1, KAPPA_MIN, KAPPA_MAX))


def _interval(r: float, n: float, a: float, b: float) -> tuple[float, float]:
    lo = (1 - CREDIBLE) / 2
    return float(beta_dist.ppf(lo, r + a, n - r + b)), float(beta_dist.ppf(1 - lo, r + a, n - r + b))


def hospital_rate(r_h: int, n_h: int) -> float:
    return (r_h + 0.5) / (n_h + 1)


def _prior(n: int, ward_type: tuple[int, int] | None, hospital: tuple[int, int], kappa: float) -> tuple[float, float, str]:
    """Beta prior (a, b) of the resistance rate and the level that leans most."""
    p_h = hospital_rate(*hospital)
    if ward_type is None:
        prior, level = p_h, "hospital"
    else:
        r_t, n_t = ward_type
        prior = shrunk_rate(r_t, n_t, p_h * kappa, (1 - p_h) * kappa)
        w_ward = n / (n + kappa)
        w_type = (1 - w_ward) * n_t / (n_t + kappa)
        level = max([("ward", w_ward), ("ward_type", w_type), ("hospital", 1 - w_ward - w_type)], key=lambda x: x[1])[0]
    return prior * kappa, (1 - prior) * kappa, level


def estimate(r: int, n: int, ward_type: tuple[int, int] | None, hospital: tuple[int, int], kappa: float) -> Estimate:
    """Shrunk resistance with range, prior weight and the prior level that leans most.

    ward_type is (R, n) of the other wards of the same type, or None for a pooled hospital row,
    whose prior is the hospital rate itself.
    """
    a, b, level = _prior(n, ward_type, hospital, kappa)
    low, high = _interval(r, n, a, b)
    return Estimate(
        value=shrunk_rate(r, n, a, b), low=low, high=high, n=int(n), prior_level=level,  # type: ignore[arg-type]
        prior_weight=round(kappa / (n + kappa), 4), small_sample=n < MIN_ISOLATES,
        raw_rate=(r / n) if n >= MIN_ISOLATES else None,
    )


def _context(store: DataStore, as_of: date, start: date, end: date, stratum: pd.DataFrame, group_cols: list[str]) -> _Context:
    win_ids = store.first_isolates(as_of, "custom", start, end)["isolate_id"]
    ann_ids = store.first_isolates(as_of, "custom", prior_start(start, end), end)["isolate_id"]
    win = stratum[stratum["isolate_id"].isin(win_ids)]
    ann = stratum[stratum["isolate_id"].isin(ann_ids)]
    ann_ward = _counts(ann, [*group_cols, "ward_code"])

    per_key: dict[tuple, tuple[list[int], list[int]]] = {}
    for k, (_, _, r, n) in ann_ward.items():
        rs, ns = per_key.setdefault(k[:-1], ([], []))
        rs.append(r)
        ns.append(n)
    fitted = {k: fit_kappa(np.array(rs), np.array(ns)) for k, (rs, ns) in per_key.items()}
    known = [v for v in fitted.values() if v is not None]
    fallback = median(known) if known else KAPPA_FALLBACK
    return _Context(
        group_cols=group_cols,
        win=win,
        ann_ward=ann_ward,
        ann_type=_counts(ann, [*group_cols, "ward_type"]),
        ann_hosp=_counts(ann, group_cols),
        kappa={k: v if v is not None else fallback for k, v in fitted.items()},
        kappa_fallback=fallback,
    )


def _rn(c: Counts | None) -> tuple[int, int]:
    return (c[2], c[3]) if c else (0, 0)


def _cells(store: DataStore, ctx: _Context, wards: list[str | None], all_keys: bool = False) -> list[Cell]:
    ward_types = dict(zip(store.tables.wards["ward_code"], store.tables.wards["ward_type"]))
    cells: list[Cell] = []
    for ward in wards:
        win_counts = _counts(ctx.win[ctx.win["ward_code"] == ward] if ward else ctx.win, ctx.group_cols)
        keys = set(win_counts)
        if ward or all_keys:  # also show cells with no isolates in the window, resting on the prior
            keys |= set(ctx.ann_hosp)
        for key in keys:
            hosp = _rn(ctx.ann_hosp.get(key))
            kappa = ctx.kappa.get(key, ctx.kappa_fallback)
            ward_type = None
            if ward:  # the other wards of the same type: leave this ward's own isolates out
                r_t, n_t = _rn(ctx.ann_type.get((*key, ward_types[ward])))
                r_w, n_w = _rn(ctx.ann_ward.get((*key, ward)))
                ward_type = (r_t - r_w, n_t - n_w)
            s_, i_, r_, n_ = win_counts.get(key, (0, 0, 0, 0))
            named = dict(zip(ctx.group_cols, key))
            a, b, _ = _prior(n_, ward_type, hosp, kappa)
            cells.append(
                Cell(ward=ward, specimen=named.get("specimen"), organism=named["organism"], drug=named["drug"],
                     s=s_, i=i_, r=r_, estimate=estimate(r_, n_, ward_type, hosp, kappa),
                     extra={"posterior": (r_ + a, n_ - r_ + b)})  # Beta of the resistance rate
            )
    cells.sort(key=lambda c: (-c.estimate.n, c.organism, c.drug))
    return cells


def estimate_cells(
    store: DataStore, as_of: date, start: date, end: date, f: Filters, group_cols: list[str] = CELL,
    wards: list[str | None] | None = None, stratum: pd.DataFrame | None = None, all_keys: bool = False,
) -> list[Cell]:
    """Estimates per ward and group_cols for the window start..end.

    `wards` lists the wards to estimate (None is the pooled hospital); default is [f.ward].
    `stratum` replaces the S/I/R rows of the filters (coverage adds regimen rows); `all_keys`
    also returns the cells that have isolates only in the prior period.
    """
    ctx = _context(store, as_of, start, end, stratum if stratum is not None else _stratum(store, f), group_cols)
    return _cells(store, ctx, wards if wards is not None else [f.ward], all_keys)


def weekly_series(
    store: DataStore, as_of: date, f: Filters, wards: list[str], date_from: date, date_to: date, window_days: int = 28,
) -> dict[str, list[dict]]:
    """Per week (Monday start) the shrunk rate over the trailing window ending that Sunday, never past as_of.

    Each point is what that week's as_of would have shown, so the series replays the live estimate.
    Specimens are pooled unless f.specimen is set. 'hospital' is the 12-month hospital rate at the
    top of the prior chain.
    """
    if f.organism is None or f.drug is None:
        raise ValueError("a series needs one organism and one drug")
    key = (f.organism, f.drug)
    stratum = _stratum(store, f)
    out: dict[str, list[dict]] = {w: [] for w in [*wards, "hospital"]}
    monday = pd.Timestamp(date_from) - pd.Timedelta(days=pd.Timestamp(date_from).weekday())
    while monday.date() <= min(date_to, as_of):
        week = monday.date()
        point_end = min(week + timedelta(days=6), as_of)
        ctx = _context(store, as_of, point_end - timedelta(days=window_days - 1), point_end, stratum, ["organism", "drug"])
        for c in _cells(store, ctx, list(wards)):
            e = c.estimate
            out[c.ward].append({"week_start": week, "n": e.n, "r": c.r, "raw_rate": e.raw_rate,
                                "shrunk_rate": e.value, "low": e.low, "high": e.high})
        r_h, n_h = _rn(ctx.ann_hosp.get(key))
        low, high = _interval(r_h, n_h, 0.5, 0.5)
        out["hospital"].append({"week_start": week, "n": n_h, "r": r_h,
                                "raw_rate": r_h / n_h if n_h >= MIN_ISOLATES else None,
                                "shrunk_rate": hospital_rate(r_h, n_h), "low": low, "high": high})
        monday += pd.Timedelta(days=7)
    return out


def _elevated_blocks(blocks: dict[int, tuple[int, int]]) -> set[int]:
    """Runs of 4-week blocks clearly above the rest of the year, peeled off one run at a time.

    Candidates are runs of 1 to MAX_RUN_BLOCKS consecutive blocks, so a cluster split across a
    block edge is still seen whole. Each run is tested against the rest of the year with a
    one-sided Fisher exact test, Bonferroni-corrected over the candidates.
    """
    elevated: set[int] = set()
    r_b = np.array([blocks.get(b, (0, 0))[0] for b in range(N_BLOCKS)])
    n_b = np.array([blocks.get(b, (0, 0))[1] for b in range(N_BLOCKS)])
    while True:
        runs = [
            range(a, a + length)
            for length in range(1, MAX_RUN_BLOCKS + 1)
            for a in range(N_BLOCKS - length + 1)
            if not elevated.intersection(range(a, a + length))
        ]
        if not runs:
            return elevated
        keep = np.array([b not in elevated for b in range(N_BLOCKS)])
        total_r, total_n = r_b[keep].sum(), n_b[keep].sum()
        r = np.array([r_b[list(run)].sum() for run in runs])
        n = np.array([n_b[list(run)].sum() for run in runs])
        rest_r, rest_n = total_r - r, total_n - n
        ok = (n > 0) & (rest_n > 0) & (r * rest_n > rest_r * n)  # run rate above the rest
        if not ok.any():
            return elevated
        # P(X >= r) for X ~ Hypergeom(total_n, total_r, n): the one-sided Fisher exact p-value
        p = np.where(ok, hypergeom.sf(r - 1, total_n, total_r, n), 1.0)
        best = int(np.argmin(p))
        if p[best] * len(runs) >= FAMILY_ALPHA:
            return elevated
        elevated.update(runs[best])


def flag_outbreak_inflation(store: DataStore, as_of: date, end: date, f: Filters, annual: list[Cell]) -> None:
    """Mark annual ward cells whose 12-month rate is lifted by a past outbreak.

    Raw against raw: a cell is inflated when some earlier weeks are significantly above the rest
    of the year, the latest 4-week block is not among them (the outbreak is over; a live one is
    an alert), and leaving the elevated weeks out lowers the 12-month rate by at least MIN_EXCESS.
    """
    if f.ward is None:
        return
    stratum = _stratum(store, f)
    ids = store.first_isolates(as_of, "custom", end - timedelta(days=364), end)["isolate_id"]
    ann = stratum[stratum["isolate_id"].isin(ids) & (stratum["ward_code"] == f.ward)].copy()
    ann["block"] = (pd.Timestamp(end) - ann["sample_date"]).dt.days // BLOCK_DAYS
    by_cell: dict[tuple, dict[int, tuple[int, int]]] = {}
    for (*key, block), (_, _, r, n) in _counts(ann, [*CELL, "block"]).items():
        by_cell.setdefault(tuple(key), {})[block] = (r, n)
    for c in annual:
        n_year = c.s + c.i + c.r
        blocks = by_cell.get((c.specimen, c.organism, c.drug))
        if n_year < MIN_ISOLATES or not blocks:
            continue
        elevated = _elevated_blocks(blocks)
        if not elevated or 0 in elevated:
            continue
        r_out = sum(blocks[b][0] for b in elevated)
        n_out = sum(blocks[b][1] for b in elevated)
        without = (c.r - r_out) / (n_year - n_out)
        if c.r / n_year - without >= MIN_EXCESS:
            c.outbreak_inflated = True
            c.rate_without_outbreak = without
