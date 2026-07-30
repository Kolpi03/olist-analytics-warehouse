# Why Olist Is Losing Customers

**An analytics warehouse over 100K Brazilian e-commerce orders, built in MySQL 8.**

> **Finding:** Customers whose first order arrives late repeat at `__%`, versus
> `__%` for customers whose first order arrives on time. Delivery reliability —
> not price, not category — is the strongest predictor of whether a first-time
> buyer ever comes back. `__` sellers, `__%` of the marketplace, account for
> half of all late deliveries.
>
> *(Fill the blanks from your own run. Never publish a number you did not measure.)*

![Lateness vs review score](docs/figures/lateness_vs_review.png)
## Live dashboard

![Dashboard overview](docs/figures/fig1.png)

Sellers flagged for delivery SLA action (30+ orders, 25%+ late):

![Seller escalation list](docs/figures/fig2.png)

Category-level revenue and delivery quality:

![Category performance](docs/figures/fig3.png)
---

## The three recommendations

1. **Stop promising delivery dates you cannot hit.** Orders delivered *before*
   the promised date average `__`/5; orders 8+ days late average `__`/5.
   Padding the estimate costs nothing and protects the review.
2. **Put the `__` ESCALATE-flagged sellers on a delivery SLA.** They carry
   `__%` of revenue but generate `__%` of late deliveries — a small, tractable
   list, not a platform-wide problem.
3. **Trigger a save-offer on any 1–2 star first-order review within 48 hours.**
   That cohort is `__` customers a month and repeats at `__%`; a recovery
   campaign has a large, well-defined target.

---

## Why MySQL and not Oracle

This project uses MySQL 8.0. The SQL that matters for analyst work — CTEs,
window functions, `RANK`/`NTILE`, running totals — is ANSI standard and
transfers directly to Oracle, PostgreSQL, Snowflake, or BigQuery. Where MySQL
forced a workaround (no `MEDIAN`, no materialised views, no `FULL OUTER JOIN`),
the workaround is commented in the script, because knowing *where a dialect
stops* is itself worth demonstrating.

---

## Architecture

```
data/raw/*.csv  ──prep_csvs.py──►  data/clean/*.csv
                                        │ LOAD DATA LOCAL INFILE
                                        ▼
                                   stg_*  (9 tables, all TEXT)
                                        │ 04_transform.sql
                                        ▼
              ┌──── dim_date ─── dim_customer ─── dim_product ────┐
              │     dim_seller ─── dim_geography                  │
              │                                                   │
              └──►  fact_orders ── fact_order_items ── fact_payments
                                        │ 10_summary_tables.sql
                                        ▼
                             rpt_monthly_kpis, rpt_seller_scorecard,
                             rpt_category_performance   ──►  Streamlit
```

---

## The one modelling decision that changes every number

Olist ships **two** customer keys:

| Column | Distinct values | What it actually is |
|---|---|---|
| `customer_id` | 99,441 | a fresh key minted for **every order** |
| `customer_unique_id` | 96,096 | the **person** |

Join on `customer_id` and Olist looks like a business with almost no repeat
customers. That is an artefact of the key, not a fact about the business.
`dim_customer` is therefore built at `customer_unique_id` grain, with
`map_customer_id` resolving the per-order key onto it.

`06_analysis_retention.sql` reports the repeat rate **both ways** on purpose,
and `05_data_quality.sql` has a check that fails the build if the two grains
ever collapse to the same count.

---

## Repo layout

```
sql/
  01_create_staging.sql        9 landing tables, everything TEXT
  02_load_data.sql             LOAD DATA LOCAL INFILE + row-count receipt
  03_create_warehouse.sql      star schema DDL, FKs, quality audit table
  04_transform.sql             typed load, derived measures, idempotent
  05_data_quality.sql          14-check test suite writing PASS/FAIL rows
  06_analysis_retention.sql    cohorts, RFM, time-to-second-order
  07_analysis_delivery.sql     funnel, lateness → review → churn, sizing
  08_analysis_revenue_sellers.sql  MoM split, Pareto, scorecard, freight
  09_performance_tuning.sql    EXPLAIN ANALYZE before/after, index + rewrite
  10_summary_tables.sql        rpt_* tables, stored proc, scheduled event
scripts/
  prep_csvs.py                 makes the CSVs LOAD DATA-safe
  analysis.py                  correlations + the four README figures
dashboard/
  app.py                       Streamlit, reads only rpt_* tables
docs/
  findings.md                  the one-page memo
  performance.md               measured before/after timings
  figures/
```

---

## Running it

**Prerequisites:** MySQL 8.0+ (8.0 is required — 5.7 has no CTEs or window
functions), Python 3.9+.

```bash
# 1. Get the data (see "Downloading the dataset" below) into data/raw/
pip install pandas sqlalchemy pymysql matplotlib scipy streamlit
python scripts/prep_csvs.py --raw data/raw --out data/clean

# 2. Enable local file loading, then run the pipeline in order.
mysql -u root -p -e "SET GLOBAL local_infile = 1;"
mysql --local-infile=1 -u root -p < sql/01_create_staging.sql
mysql --local-infile=1 -u root -p < sql/02_load_data.sql     # ~60s, 1M geo rows
mysql -u root -p < sql/03_create_warehouse.sql
mysql -u root -p < sql/04_transform.sql
mysql -u root -p < sql/05_data_quality.sql                   # must be all PASS

# 3. Analysis
mysql -u root -p < sql/06_analysis_retention.sql
mysql -u root -p < sql/07_analysis_delivery.sql
mysql -u root -p < sql/08_analysis_revenue_sellers.sql
mysql -u root -p < sql/09_performance_tuning.sql             # record the timings
mysql -u root -p < sql/10_summary_tables.sql

# 4. Figures and dashboard
python scripts/analysis.py --password YOURPASS
streamlit run dashboard/app.py
```

`01_create_staging.sql` drops and recreates the whole `olist` database, so
always run the scripts in numeric order.

---

## Downloading the dataset

**Brazilian E-Commerce Public Dataset by Olist**, published by Olist under
CC BY-NC-SA 4.0. Roughly 100K orders placed between 2016 and 2018, across nine
related files.

**Manual:** search Kaggle for "Brazilian E-Commerce Public Dataset by Olist"
(publisher: `olistbr`), sign in, hit **Download**, and unzip all nine CSVs
into `data/raw/`.

**CLI:**
```bash
pip install kaggle
# Kaggle > Settings > API > Create New Token  ->  saves kaggle.json
mkdir -p ~/.kaggle && mv ~/Downloads/kaggle.json ~/.kaggle/ && chmod 600 ~/.kaggle/kaggle.json
kaggle datasets download -d olistbr/brazilian-ecommerce -p data/raw --unzip
```

Expected files and approximate row counts:

| File | Rows |
|---|---|
| `olist_orders_dataset.csv` | 99,441 |
| `olist_order_items_dataset.csv` | 112,650 |
| `olist_order_payments_dataset.csv` | 103,886 |
| `olist_order_reviews_dataset.csv` | 99,224 |
| `olist_customers_dataset.csv` | 99,441 |
| `olist_products_dataset.csv` | 32,951 |
| `olist_sellers_dataset.csv` | 3,095 |
| `olist_geolocation_dataset.csv` | 1,000,163 |
| `product_category_name_translation.csv` | 71 |

Verify these against the receipt printed by `02_load_data.sql`. Counts are from
the 2018 v2 release; if yours differ, update the assertions in
`05_data_quality.sql` rather than ignoring the failures.

**Do not commit the CSVs.** `data/` is gitignored — the repo should hold code,
not 120MB of someone else's data.

---

## Known limitations

Stating these is not weakness; it is the difference between an analyst and a
dashboard operator.

- **Correlation, not causation.** Late delivery and churn move together, but
  the same underlying factor (remote address, bulky item, unreliable seller)
  could drive both. A proper answer needs an experiment, not this dataset.
- **Reviews are self-selected.** Roughly 1% of orders have no review at all,
  and unhappy customers are more likely to leave one. Absolute scores are
  biased; the *relative* comparison across delivery buckets is more defensible.
- **Two-year window.** Olist grew fast over the period, so late cohorts have
  less time to produce a repeat purchase. Cohort tables are truncated at 12
  months for this reason.
- **No cost data.** "Recoverable revenue" is gross, not margin. Without COGS
  and delivery cost, it is an upper bound.
- **`payment_value` and `order_value` do not reconcile exactly** because of
  vouchers and instalment rounding. The quality suite allows 1% tolerance
  rather than pretending to an exact match.

---

## What I would build next

- Load daily rather than full-refresh, with a watermark column and `ON
  DUPLICATE KEY UPDATE` upserts.
- Slowly-changing dimension (Type 2) on `dim_seller` to track when a seller's
  performance band changed.
- A logistic model on `is_repeat_customer` to rank the drivers of churn against
  each other rather than one at a time.

---

*Data: Olist Store, CC BY-NC-SA 4.0. This is an independent analysis and is not
affiliated with or endorsed by Olist.*
