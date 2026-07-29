"""
prep_csvs.py
------------
MySQL's LOAD DATA INFILE chokes on the Olist review CSV because the free-text
comment fields contain embedded newlines inside quoted values. It also has no
concept of "empty string means NULL" for typed columns.

This script normalises all nine raw CSVs into LOAD DATA-safe files:
  - strips CR/LF and tabs from every text field
  - writes \\N for missing values (MySQL's NULL sentinel)
  - drops the two free-text review columns we never analyse
  - writes UTF-8 without a BOM

Usage:
    python scripts/prep_csvs.py --raw data/raw --out data/clean
"""

import argparse
import os
import sys

import pandas as pd

FILES = [
    "olist_customers_dataset.csv",
    "olist_geolocation_dataset.csv",
    "olist_order_items_dataset.csv",
    "olist_order_payments_dataset.csv",
    "olist_order_reviews_dataset.csv",
    "olist_orders_dataset.csv",
    "olist_products_dataset.csv",
    "olist_sellers_dataset.csv",
    "product_category_name_translation.csv",
]

# Free-text columns dropped: they are the only source of embedded newlines and
# nothing downstream reads them.
DROP_COLS = {"review_comment_title", "review_comment_message"}


def clean_frame(df: pd.DataFrame) -> pd.DataFrame:
    df = df.drop(columns=[c for c in df.columns if c in DROP_COLS], errors="ignore")
    for col in df.columns:
        if df[col].dtype == object:
            df[col] = (
                df[col]
                .astype(str)
                .str.replace(r"[\r\n\t]+", " ", regex=True)
                .str.strip()
                .replace({"": None, "nan": None, "None": None})
            )
    return df


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", default="data/raw")
    ap.add_argument("--out", default="data/clean")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    missing = [f for f in FILES if not os.path.exists(os.path.join(args.raw, f))]
    if missing:
        print("Missing from --raw:\n  " + "\n  ".join(missing), file=sys.stderr)
        return 1

    for fname in FILES:
        src = os.path.join(args.raw, fname)
        dst = os.path.join(args.out, fname)
        df = pd.read_csv(src, dtype=str, keep_default_na=False, na_values=[""])
        rows_in = len(df)
        df = clean_frame(df)
        df.to_csv(
            dst,
            index=False,
            na_rep="\\N",
            encoding="utf-8",
            lineterminator="\n",
        )
        print(f"{fname:48s} {rows_in:>9,} rows -> {dst}")

    print("\nDone. Row counts above are the numbers to assert in 05_data_quality.sql.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
