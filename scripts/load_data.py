#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["psycopg[binary]>=3.2"]
# ///
"""Create the schema and load the six dataset CSVs into Postgres.

    uv run scripts/load_data.py --dsn "$(az keyvault secret show --vault-name <kv> -n database-url --query value -o tsv)"

The load runs in one transaction: the dataset tables are truncated, reloaded with COPY, and the
row counts are compared with the CSV row counts before anything is committed. Re-running gives
the same result. Application tables (user_dashboards) are never touched.
"""

import argparse
import csv
import os
import sys
from pathlib import Path

import psycopg

ROOT = Path(__file__).resolve().parent.parent
# Parents before children, so foreign keys hold at every step.
TABLES = ["wards", "antibiotics", "patients", "cultures", "isolates", "susceptibility"]


def csv_rows(path: Path) -> int:
    with path.open(newline="", encoding="utf-8") as f:
        return sum(1 for _ in csv.reader(f)) - 1  # minus the header


def copy_csv(cur: psycopg.Cursor, table: str, path: Path) -> None:
    with path.open(newline="", encoding="utf-8") as f:
        columns = next(csv.reader(f))
    cols = ", ".join(columns)
    # Empty strings become NULL (admission_date for outpatients, quantity for blood).
    sql = f"COPY {table} ({cols}) FROM STDIN WITH (FORMAT csv, HEADER true, NULL '')"
    with cur.copy(sql) as copy, path.open("rb") as f:
        while chunk := f.read(1 << 20):
            copy.write(chunk)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dsn", default=os.environ.get("DATABASE_URL"), help="default: $DATABASE_URL")
    ap.add_argument("--data-dir", type=Path, default=ROOT / "data" / "synthetic_microbiology_dataset")
    ap.add_argument("--schema", type=Path, default=ROOT / "backend" / "schema.sql")
    args = ap.parse_args()
    if not args.dsn:
        ap.error("pass --dsn or set DATABASE_URL")

    expected = {t: csv_rows(args.data_dir / f"{t}.csv") for t in TABLES}

    with psycopg.connect(args.dsn, connect_timeout=15) as conn:
        with conn.cursor() as cur:
            cur.execute(args.schema.read_text(encoding="utf-8"))
            cur.execute("TRUNCATE " + ", ".join(reversed(TABLES)))
            for t in TABLES:
                copy_csv(cur, t, args.data_dir / f"{t}.csv")

            print(f"{'table':<16}{'csv rows':>10}{'db rows':>10}")
            bad = []
            for t in TABLES:
                n = cur.execute(f"SELECT count(*) FROM {t}").fetchone()[0]
                print(f"{t:<16}{expected[t]:>10}{n:>10}{'' if n == expected[t] else '  MISMATCH'}")
                if n != expected[t]:
                    bad.append(t)
            if bad:
                conn.rollback()
                print(f"Row counts differ for {', '.join(bad)}; rolled back.", file=sys.stderr)
                return 1
            cur.execute("ANALYZE")
        conn.commit()
    print("Loaded and committed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
