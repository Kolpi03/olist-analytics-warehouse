# Performance: measured before / after

MySQL 8.0.46, InnoDB, default buffer pool. `EXPLAIN ANALYZE` timings, each
query run three times with the **third** reading recorded (the first two pay
for cold buffer pool reads). Dataset: 99,441 orders / 112,650 line items,
loaded and verified against the real Olist dataset (14/14 quality checks
pass).

| Query | Before | After | Change | What changed |
|---|---:|---:|---:|---|
| Q1 Monthly revenue split | 105 ms | 100 ms | — | no meaningful gain, see note |
| Q2 Delivery lateness cut | 78 ms | **45 ms** | **1.7x** | covering `ix_fo_late_review` |
| Q3 Seller scorecard | 640 ms | **457 ms** | **1.4x** | covering `ix_foi_seller_cover` |
| Q4 RFM customer base | 324 ms | **137 ms** | **2.4x** | covering `ix_fo_status_purchase_cover` |
| Q5 Per-customer average | 914 ms | **284 ms** | **3.2x** | correlated subquery -> window function |

## Index cost

| Table | Data MB | Index MB | Overhead |
|---|---:|---:|---:|
| fact_orders | 23.55 | 43.22 | 184% |
| fact_order_items | 11.52 | 27.64 | 240% |
| fact_payments | 9.52 | 12.06 | 127% |

Index bytes exceed data bytes. On a read-heavy analytics table that trade is
fine; on a write-heavy OLTP table it would not be, and the covering indexes
would need to be narrower.

## Two results worth reporting because they were negative

**1. My first index made Q2 three times slower.** `(is_late, review_score,
delay_days)` looked reasonable, but the query filters on
`delivered_customer_ts`, which was not in the index, so MySQL walked the
index and then did one random row lookup per entry: 78 ms became 220 ms.
Adding `delivered_customer_ts` restored the covering property and took it to
45 ms.

**2. Q1 could not be improved.** `order_status <> 'canceled'` is an
inequality on the leading column, so the index can only be scanned, not
sought, and the `GROUP BY EXTRACT(YEAR_MONTH ...)` still needs a temporary
table. A MySQL 8 functional index on the extracted expression removed the
temp table but ran 4x slower, having lost the covering property. Reverted.

## Benchmark trap

With `LIMIT 5000` on both formulations, the correlated subquery appeared
*faster* than the window function. MySQL evaluates the subquery only for
rows it actually returns, whereas the window function must sort every
partition before emitting the first row. The `LIMIT` was measuring startup
cost, not throughput. Wrapping both in `SELECT COUNT(*) FROM (...)` forces
full materialisation and gives the honest 3.2x.

## Verification (re-run independently)

Two spot checks, re-run directly against the loaded warehouse to confirm
the headline finding before publishing it:

| Query | Result |
|---|---:|
| `SELECT COUNT(*) FROM fact_orders;` | 99,441 |
| `AVG(review_score)` where `delay_days <= -10` (10+ days early) | 4.3227 |
| `AVG(review_score)` where `delay_days > 14` (2+ weeks late) | 1.7288 |

Both figures match the pipeline's original output, confirming the
delay-to-review collapse is reproducible and not an artifact of a single run.
