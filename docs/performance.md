# Performance: measured before / after

Fill this in from your own `09_performance_tuning.sql` run. Take the
`actual time=` figure from each `EXPLAIN ANALYZE`, run each query twice, and
record the **second** reading (the first pays for cold InnoDB buffer pool reads).

| Query | Before (ms) | After (ms) | Speedup | What changed |
|---|---|---|---|---|
| Monthly revenue split | | | | covering index `ix_fo_status_purchase_cover` |
| Delivery lateness cut | | | | `ix_fo_late_review` on derived columns |
| Seller scorecard | | | | covering index `ix_foi_seller_cover` |
| RFM customer base | | | | covering index, index-only scan |
| Per-customer average | | | | correlated subquery → window function |

Index cost (from the `information_schema` query at the end of the script):

| Table | Data MB | Index MB | Overhead % |
|---|---|---|---|
| fact_orders | | | |
| fact_order_items | | | |

**Note on the plan output.** Look for `Covering index scan` replacing
`Table scan`, and for `Nested loop` replacing `hash join` on the seller query.
The line that matters is the innermost one — that is where the time went.
