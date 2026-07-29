-- =====================================================================
-- 09_performance_tuning.sql
-- The section that turns "I wrote queries" into "I made them fast."
--
-- HOW TO USE THIS FILE
--   1. Run the BEFORE block. Copy the "actual time=" figure from each
--      EXPLAIN ANALYZE into docs/performance.md.
--   2. Run the INDEX block.
--   3. Run the AFTER block. Copy those figures too.
--   4. Your resume bullet is the delta. Measure it — never estimate it.
--
-- EXPLAIN ANALYZE actually EXECUTES the query and reports real timings
-- (MySQL 8.0.18+). Plain EXPLAIN only shows the optimiser's guess.
-- Run each twice and take the second reading, or you are timing cold
-- InnoDB buffer pool reads rather than the plan.
-- =====================================================================

USE olist;

-- ============================ BEFORE =================================

-- Q1: monthly revenue split — full scan of fact_orders, filter on a
--     non-indexed expression over purchase_ts.
EXPLAIN ANALYZE
SELECT EXTRACT(YEAR_MONTH FROM purchase_ts) AS ym,
       SUM(order_value) AS revenue,
       SUM(CASE WHEN customer_order_seq = 1 THEN order_value ELSE 0 END) AS new_rev
FROM fact_orders
WHERE order_status <> 'canceled'
GROUP BY ym;

-- Q2: the delivery-lateness cut — filters on two derived columns that
--     have no index at all.
EXPLAIN ANALYZE
SELECT is_late, COUNT(*), AVG(review_score)
FROM fact_orders
WHERE delivered_customer_ts IS NOT NULL AND review_score IS NOT NULL
GROUP BY is_late;

-- Q3: seller scorecard — the expensive one. Two joins plus aggregation.
EXPLAIN ANALYZE
SELECT ds.seller_id, COUNT(DISTINCT foi.order_id) AS orders,
       SUM(foi.price) AS revenue, AVG(fo.is_late) AS late_rate
FROM fact_order_items foi
JOIN dim_seller  ds ON ds.seller_sk = foi.seller_sk
JOIN fact_orders fo ON fo.order_id  = foi.order_id
GROUP BY ds.seller_id
HAVING orders >= 30;

-- Q4: customer-level RFM base.
EXPLAIN ANALYZE
SELECT customer_sk, MAX(purchase_ts), COUNT(*), SUM(order_value)
FROM fact_orders
WHERE order_status <> 'canceled'
GROUP BY customer_sk;

-- ============================ INDEXES ================================
-- Each index below is justified. An index you cannot justify is an
-- index you should not ship: every one slows writes and costs disk.

-- Q1/Q4: covering index. status filter first (equality-ish), then the
-- columns the aggregate needs, so InnoDB never touches the base row.
CREATE INDEX ix_fo_status_purchase_cover
    ON fact_orders (order_status, purchase_ts, customer_sk, order_value, customer_order_seq);

-- Q2: the two derived columns used by every delivery-quality query.
CREATE INDEX ix_fo_late_review
    ON fact_orders (is_late, review_score, delay_days);

-- Q3: lets the seller aggregation walk the index in seller order
-- instead of building a hash table over 112k line items.
CREATE INDEX ix_foi_seller_cover
    ON fact_order_items (seller_sk, order_id, price, freight_value);

-- Delivery-band queries scan on delay_days directly.
CREATE INDEX ix_fo_delay
    ON fact_orders (delay_days);

ANALYZE TABLE fact_orders, fact_order_items, dim_seller, dim_customer;

-- ============================ AFTER ==================================
-- Re-run the identical four statements and record the new timings.

EXPLAIN ANALYZE
SELECT EXTRACT(YEAR_MONTH FROM purchase_ts) AS ym,
       SUM(order_value) AS revenue,
       SUM(CASE WHEN customer_order_seq = 1 THEN order_value ELSE 0 END) AS new_rev
FROM fact_orders
WHERE order_status <> 'canceled'
GROUP BY ym;

EXPLAIN ANALYZE
SELECT is_late, COUNT(*), AVG(review_score)
FROM fact_orders
WHERE delivered_customer_ts IS NOT NULL AND review_score IS NOT NULL
GROUP BY is_late;

EXPLAIN ANALYZE
SELECT ds.seller_id, COUNT(DISTINCT foi.order_id) AS orders,
       SUM(foi.price) AS revenue, AVG(fo.is_late) AS late_rate
FROM fact_order_items foi
JOIN dim_seller  ds ON ds.seller_sk = foi.seller_sk
JOIN fact_orders fo ON fo.order_id  = foi.order_id
GROUP BY ds.seller_id
HAVING orders >= 30;

EXPLAIN ANALYZE
SELECT customer_sk, MAX(purchase_ts), COUNT(*), SUM(order_value)
FROM fact_orders
WHERE order_status <> 'canceled'
GROUP BY customer_sk;

-- ---------------------------------------------------------------------
-- Index footprint — the cost side of the trade, worth reporting too.
-- ---------------------------------------------------------------------
SELECT
    table_name,
    ROUND(data_length  / 1024 / 1024, 2) AS data_mb,
    ROUND(index_length / 1024 / 1024, 2) AS index_mb,
    ROUND(100 * index_length / NULLIF(data_length, 0), 1) AS index_overhead_pct
FROM information_schema.tables
WHERE table_schema = 'olist' AND table_name LIKE 'fact%'
ORDER BY index_length DESC;

-- ---------------------------------------------------------------------
-- A REWRITE, not just an index. The correlated subquery below runs once
-- per row; the window-function version runs once total. Time both and
-- report the difference — rewrites usually beat indexes, and knowing
-- that is worth more in an interview than knowing index syntax.
-- ---------------------------------------------------------------------

-- Slow: correlated subquery
EXPLAIN ANALYZE
SELECT fo.order_id, fo.order_value,
       (SELECT AVG(f2.order_value)
        FROM fact_orders f2
        WHERE f2.customer_sk = fo.customer_sk) AS cust_avg
FROM fact_orders fo
LIMIT 5000;

-- Fast: single pass with a window function
EXPLAIN ANALYZE
SELECT order_id, order_value,
       AVG(order_value) OVER (PARTITION BY customer_sk) AS cust_avg
FROM fact_orders
LIMIT 5000;
