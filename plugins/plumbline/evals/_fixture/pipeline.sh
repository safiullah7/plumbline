#!/usr/bin/env bash
# Shared eval fixture for v0.4b: Storeroll, a Python nightly data pipeline that
# rolls store sales up into daily totals (surface data). Module "rollup" has a
# vision and one finished feature (01-store-totals) whose criteria the tests are
# named after. Sourcing this file leaves one commit on main.
#   source "$(dirname "$0")/../_fixture/pipeline.sh"
set -e
source "$(dirname "${BASH_SOURCE[0]}")/profile.sh"

git init -q -b main
git config user.name eval
git config user.email eval@example.com
git config core.autocrlf false
mkdir -p rollup tests dags data/sample docs/product/rollup

project_profile no "customer email addresses in the raw sales export" "| data | Python | rollup/** dags/** tests/** data/** | python -m rollup.run --date 2026-10-01 --in data/sample | mypy rollup | ruff check . | pytest |"

cat > docs/product/rollup/vision.md <<'EOT'
# Rollup vision

Owner: product engineer

## Who it's for
Finance analysts who read the daily sales dashboard, and the data engineer who
runs the nightly pipeline behind it.

## Problem
Store sales arrive as CSV exports from 40 stores. Totals on the dashboard are
rebuilt by hand and disagree with the stores' own numbers.

## Product principles
- A rerun for the same day gives the same totals, never doubled ones.
- A bad row is set aside and counted; it never stops the night's run.
- Customer email addresses never reach the totals table or the logs.

## Features
Each feature is named by the outcome it changes for a user. Folder:
docs/product/rollup/.
| Feature | Goal | Outcome (measurable) | Why next | Status |
| --- | --- | --- | --- | --- |
| 01-store-totals | Daily totals per store | Dashboard totals match the stores' numbers to the cent on 30 days of data | The dashboard is rebuilt by hand today | Done |
EOT

cat > pyproject.toml <<'EOT'
[project]
name = "storeroll"
version = "0.2.0"
description = "Nightly rollup of store sales into daily totals"
requires-python = ">=3.11"
dependencies = [
  "pandas>=2.2",
  "sqlalchemy>=2.0",
]

[project.optional-dependencies]
dev = ["pytest>=8", "mypy>=1.10", "ruff>=0.5"]

[tool.pytest.ini_options]
testpaths = ["tests"]
EOT

cat > rollup/__init__.py <<'EOT'
"""Nightly rollup of store sales into daily totals."""
EOT

cat > rollup/extract.py <<'EOT'
"""Read one day's CSV exports, one file per store."""
from pathlib import Path

import pandas as pd

COLUMNS = ["store_id", "sold_at", "sku", "quantity", "unit_price_cents", "customer_email"]


def read_day(folder: Path, day: str) -> pd.DataFrame:
    frames = [pd.read_csv(f, dtype=str) for f in sorted(folder.glob(f"*-{day}.csv"))]
    if not frames:
        return pd.DataFrame(columns=COLUMNS)
    return pd.concat(frames, ignore_index=True)[COLUMNS]
EOT

cat > rollup/transform.py <<'EOT'
"""Clean the rows and total them per store."""
import pandas as pd


def split_valid(rows: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Return (valid, rejected). A row is rejected when quantity or price isn't a positive integer."""
    qty = pd.to_numeric(rows["quantity"], errors="coerce")
    price = pd.to_numeric(rows["unit_price_cents"], errors="coerce")
    ok = (qty > 0) & (price > 0) & (qty % 1 == 0) & (price % 1 == 0)
    return rows[ok].copy(), rows[~ok].copy()


def daily_totals(valid: pd.DataFrame, day: str) -> pd.DataFrame:
    valid = valid.assign(
        total_cents=valid["quantity"].astype(int) * valid["unit_price_cents"].astype(int),
    )
    totals = valid.groupby("store_id", as_index=False)["total_cents"].sum()
    totals.insert(0, "day", day)
    return totals  # no customer_email column: it must not reach the totals table
EOT

cat > rollup/load.py <<'EOT'
"""Write a day's totals. Rerunning a day replaces that day's rows."""
import pandas as pd
from sqlalchemy import Engine, text


def replace_day(engine: Engine, totals: pd.DataFrame, day: str) -> None:
    with engine.begin() as conn:
        conn.execute(text("DELETE FROM daily_totals WHERE day = :day"), {"day": day})
        totals.to_sql("daily_totals", conn, if_exists="append", index=False)
EOT

cat > rollup/run.py <<'EOT'
"""python -m rollup.run --date YYYY-MM-DD --in <folder>"""
import argparse
import logging
from pathlib import Path

from sqlalchemy import create_engine

from . import extract, load, transform

log = logging.getLogger("rollup")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--date", required=True)
    parser.add_argument("--in", dest="folder", type=Path, required=True)
    parser.add_argument("--db", default="sqlite:///rollup.db")
    args = parser.parse_args()

    rows = extract.read_day(args.folder, args.date)
    valid, rejected = transform.split_valid(rows)
    log.info("day=%s rows=%d rejected=%d", args.date, len(rows), len(rejected))
    load.replace_day(create_engine(args.db), transform.daily_totals(valid, args.date), args.date)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
EOT

cat > dags/nightly_rollup.py <<'EOT'
"""Airflow DAG: run the rollup for yesterday at 02:00."""
from datetime import datetime

from airflow import DAG
from airflow.operators.bash import BashOperator

with DAG("nightly_rollup", schedule="0 2 * * *", start_date=datetime(2026, 1, 1), catchup=False) as dag:
    BashOperator(
        task_id="rollup",
        bash_command="python -m rollup.run --date {{ ds }} --in /data/exports",
    )
EOT

cat > data/sample/s01-2026-10-01.csv <<'EOT'
store_id,sold_at,sku,quantity,unit_price_cents,customer_email
s01,2026-10-01T09:12:00,A100,2,450,ana@example.com
s01,2026-10-01T09:40:00,B200,1,1299,
s01,2026-10-01T10:05:00,A100,0,450,bo@example.com
EOT

cat > tests/test_rollup.py <<'EOT'
"""Tests are named after the feature 01 acceptance criteria."""
import pandas as pd

from rollup import transform


def rows(*items):
    return pd.DataFrame(items, columns=["store_id", "sold_at", "sku", "quantity", "unit_price_cents", "customer_email"])


def test_AC_01_001_totals_are_summed_per_store():
    valid, _ = transform.split_valid(rows(
        ("s01", "t", "A", "2", "450", ""),
        ("s01", "t", "B", "1", "1299", ""),
        ("s02", "t", "A", "1", "450", ""),
    ))
    totals = transform.daily_totals(valid, "2026-10-01").set_index("store_id")["total_cents"]
    assert totals["s01"] == 2199
    assert totals["s02"] == 450


def test_AC_01_002_bad_rows_are_set_aside():
    valid, rejected = transform.split_valid(rows(
        ("s01", "t", "A", "0", "450", ""),
        ("s01", "t", "A", "x", "450", ""),
        ("s01", "t", "A", "1", "450", ""),
    ))
    assert len(valid) == 1
    assert len(rejected) == 2


def test_AC_01_003_emails_never_reach_the_totals():
    valid, _ = transform.split_valid(rows(("s01", "t", "A", "1", "450", "ana@example.com")))
    assert "customer_email" not in transform.daily_totals(valid, "2026-10-01").columns
EOT

git add -A
git commit -qm "Storeroll pipeline with feature 01 done"
