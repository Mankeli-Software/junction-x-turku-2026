#!/usr/bin/env python
"""Score every alert rule: weeks to detect and false alarms per ward-year.

    .venv/bin/python scripts/evaluate_alerts.py            # daily replay, about 5 minutes
    .venv/bin/python scripts/evaluate_alerts.py --quick    # weekly replay, about 1 minute
    .venv/bin/python scripts/evaluate_alerts.py --out docs/alert_evaluation.md

The script calls the same detector functions the API uses (backend/app/datalayer/alerts.py,
signals.py, trend.py) at each replay date, so the table is what the live tool would have shown.
The planted signals below are ground truth for SCORING ONLY. No detector knows a date or a ward;
the detectors are listed in DETECTORS and never read this file.

Ground truth comes from the data brief (data/AEI_ML_PIPELINE.md, issues #1 and #2):
  URO ESBL E. coli outbreak        2025-05-25 .. 2025-07-29
  ICU MRSA S. aureus cluster       2026-03-03 .. 2026-03-27
  PHC-S culture gap                2025-12-08 .. 2025-12-14
  E. coli trimethoprim drift       about 2.1 points a year from the start of the data (2023-10)
  CPE and VRE isolates             12 and 5, found by flag in the isolate table
"""

import argparse
import sys
from collections import defaultdict
from datetime import date, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "backend"))

from app.datalayer import alerts as A
from app.datalayer import signals as sig
from app.datalayer import susceptibility as S
from app.datalayer.store import get_store
from app.vocab import WARDS

END = date(2026, 9, 27)
SLACK = 28  # an alert up to this many days after the planted window ends still counts as that signal
OUTBREAKS = [  # (ward, organism, onset, end) - scoring only
    ("URO", "Escherichia coli", date(2025, 5, 25), date(2025, 7, 29)),
    ("ICU", "Staphylococcus aureus", date(2026, 3, 3), date(2026, 3, 27)),
]
GAP = ("PHC-S", date(2025, 12, 8), date(2025, 12, 14))  # (ward, first day, last day)
NAIVE_LIFT = 0.10  # baseline rule: raw 4-week rate (only shown from 30 isolates) 10 points above hospital


def episodes(days: list[date], gap: int = A.EPISODE_GAP_DAYS) -> list[tuple[date, date]]:
    out: list[list[date]] = []
    for d in sorted(days):
        if out and (d - out[-1][1]).days <= gap:
            out[-1][1] = d
        else:
            out.append([d, d])
    return [(a, b) for a, b in out]


def score_outbreaks(flagged: dict[tuple[str, str], list[date]]) -> tuple[dict[str, float | None], int]:
    """Days from onset to the first flag per planted outbreak, and the number of other episodes."""
    delay: dict[str, float | None] = {w: None for w, *_ in OUTBREAKS}
    false = 0
    for (ward, organism), days in flagged.items():
        for first, last in episodes(days):
            hit = False
            for w, o, onset, end in OUTBREAKS:
                if (ward, organism) == (w, o) and first <= end + timedelta(days=SLACK) and last >= onset:
                    hit = True
                    d = (first - onset).days
                    delay[w] = d if delay[w] is None else min(delay[w], d)
            false += not hit
    return delay, false


def naive_flags(store, day: date) -> list[tuple[str, str]]:
    """Baseline: the 30-isolate rule on raw rates. Cells under 30 isolates never show a rate, so never alert."""
    out = set()
    for stratum in (sig._strata_for(store).phenotype, sig._strata_for(store).drug):
        start, year = day - timedelta(days=sig.WINDOW_DAYS - 1), day - timedelta(days=364)
        cells = S.estimate_cells(store, day, start, day, sig.FILTERS, sig.GROUP, wards=list(WARDS), stratum=stratum)
        hosp = {(c.organism, c.drug): c.estimate.value for c in S.estimate_cells(store, day, year, day, sig.FILTERS, sig.GROUP, wards=[None], stratum=stratum)}
        for c in cells:
            if c.estimate.raw_rate is not None and c.estimate.raw_rate - hosp[(c.organism, c.drug)] >= NAIVE_LIFT:
                out.add((c.ward, c.organism))
    return sorted(out)


def fmt_delay(days: float | None) -> str:
    return "missed" if days is None else f"{days / 7:.1f} wk"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--quick", action="store_true", help="replay weekly instead of daily")
    ap.add_argument("--out", type=Path, help="also write the table to this markdown file")
    args = ap.parse_args()
    step = 7 if args.quick else 1

    store = get_store()
    start = max(store.tables.cultures["sample_date"].min().date() + timedelta(days=365), date(2024, 10, 6))
    days = [start + timedelta(days=i) for i in range(0, (END - start).days + 1, step)]
    years = (END - start).days / 365.25
    ward_years = len(WARDS) * years
    print(f"Replaying {len(days)} dates from {start} to {END} ({'weekly' if step == 7 else 'daily'})...", file=sys.stderr)

    by_kind: dict[str, dict[tuple[str, str], list[date]]] = {k: defaultdict(list) for k in ("phenotype", "drug", "combined", "naive")}
    missing_first: dict[tuple[str, date], date] = {}
    trend_first: dict[tuple[str, str], date] = {}
    for i, d in enumerate(days):
        for h in sig.hits_on(store, d):
            by_kind[h.kind][(h.ward, h.organism)].append(d)
            by_kind["combined"][(h.ward, h.organism)].append(d)
        for g in naive_flags(store, d):
            by_kind["naive"][g].append(d)
        for a in A.missing_data_alerts(store, d):
            missing_first.setdefault((a.ward, a.first_seen), d)
        for a in A.trend_alerts(store, d):
            trend_first.setdefault((a.organism, a.drugs[0]), d)
        if i % 60 == 0:
            print(f"  {d}", file=sys.stderr)

    # sentinel: every flagged isolate must alert on the day it is sampled
    iso = store.isolates(END)
    flagged_iso = iso[(iso["cpe"] == 1) | (iso["vre"] == 1)]
    late = 0
    for r in flagged_iso.itertuples():
        day = r.sample_date.date()
        late += f"sentinel-{r.isolate_id}" not in {a.alert_id for a in A.sentinel_alerts(store, day)}
    sentinel_total = len(A.sentinel_alerts(store, END))

    rows = []
    rows.append(("Sentinel: any CPE or VRE isolate", f"{len(flagged_iso)} isolates", f"{len(flagged_iso) - late} of {len(flagged_iso)}", "0 days (same day)", sentinel_total - len(flagged_iso), "n/a: every flagged isolate is a true event"))

    gap_days = [d for (w, _), d in missing_first.items() if w == GAP[0]]
    first_gap_alert = min(gap_days) if gap_days else None
    fa_missing = sum(1 for (w, _) in missing_first if w != GAP[0])
    rows.append(("Missing data: ward far below its seasonal baseline", "PHC-S gap, 1 week", "1 of 1" if gap_days else "0 of 1",
                 f"{(first_gap_alert - GAP[1]).days} days from the gap start, {(first_gap_alert - GAP[2]).days} after the gap week ended" if gap_days else "missed",
                 fa_missing, fa_missing / ward_years))

    for label, kind in [
        ("Statistical: ESBL/MRSA flag above the hospital rate", "phenotype"),
        ("Statistical: >= 2 drugs above the hospital rate", "drug"),
        ("Statistical, combined (what the API runs)", "combined"),
        ("Baseline: raw 4-week rate, shown only from 30 isolates", "naive"),
    ]:
        delay, false = score_outbreaks(by_kind[kind])
        detected = sum(v is not None for v in delay.values())
        rows.append((label, "URO ESBL, ICU MRSA", f"{detected} of 2", f"URO {fmt_delay(delay['URO'])}, ICU {fmt_delay(delay['ICU'])}", false, false / ward_years))

    t_first = trend_first.get(("Escherichia coli", "TMP"))
    t_false = sum(1 for k in trend_first if k != ("Escherichia coli", "TMP"))
    rows.append(("Trend: monthly Mann-Kendall + Sen slope", "E. coli trimethoprim drift", "1 of 1" if t_first else "0 of 1",
                 f"first significant {t_first}" if t_first else "missed", t_false, t_false / years))

    table = ["| Rule | Planted signal | Detected | Time to detect (from onset) | False alarms | False alarms per ward-year |", "| --- | --- | --- | --- | --- | --- |"]
    for label, signal, det, delay, fa, rate in rows:
        rate_s = rate if isinstance(rate, str) else f"{rate:.2f}"
        table.append(f"| {label} | {signal} | {det} | {delay} | {fa} | {rate_s} |")
    notes = [
        "",
        f"Replay: {len(days)} dates from {start} to {END}; {len(WARDS)} wards x {years:.2f} years = {ward_years:.1f} ward-years.",
        "A false alarm is an alert episode (flags less than 14 days apart merge) that matches no planted signal. The trend row's rate is per hospital-year, not per ward-year.",
        "The thresholds (99% posterior confidence, 3 resistant isolates, 3-point margin for drugs) were chosen on this dataset, which has one example of each signal, so the zero false-alarm rows are in-sample.",
    ]
    text = "\n".join(table + notes)
    print(text)
    if args.out:
        args.out.write_text("# Alert evaluation\n\nGenerated by `scripts/evaluate_alerts.py`.\n\n" + text + "\n", encoding="utf-8")
        print(f"Wrote {args.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
