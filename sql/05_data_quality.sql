-- =====================================================================
-- 05_data_quality.sql
-- A test SUITE, not a pile of ad-hoc SELECTs.
--
-- Each check INSERTs a row into data_quality_checks with a PASS/FAIL
-- verdict. That gives the project three things a query dump can't:
--   1. a single "did the load succeed" query you can run after every refresh
--   2. a historical record (run_ts) so you can see quality drift over time
--   3. something to point at when an interviewer asks "how did you know
--      your numbers were right?"
-- =====================================================================

USE olist;

DELETE FROM data_quality_checks WHERE run_ts < NOW() - INTERVAL 30 DAY;

-- ------------------------- COMPLETENESS ------------------------------

INSERT INTO data_quality_checks (check_name, severity, observed, expected, status, notes)
SELECT 'row_count_orders', 'FAIL', COUNT(*), '99441',
       CASE WHEN COUNT(*) = 99441 THEN 'PASS' ELSE 'FAIL' END,
       'fact_orders must match the source order file exactly'
FROM fact_orders;

INSERT INTO data_quality_checks (check_name, severity, observed, expected, status, notes)
SELECT 'row_count_order_items', 'FAIL', COUNT(*), '112650',
       CASE WHEN COUNT(*) = 112650 THEN 'PASS' ELSE 'FAIL' END,
       'a shortfall here means orphaned items were silently dropped'
FROM fact_order_items;

-- The headline modelling check. If these two are equal you have joined on
-- the wrong customer key and every retention number will read as zero.
INSERT INTO data_quality_checks (check_name, severity, observed, expected, status, notes)
SELECT 'distinct_persons_lt_distinct_customer_ids', 'FAIL',
       (SELECT COUNT(*) FROM dim_customer),
       '< 99441',
       CASE WHEN (SELECT COUNT(*) FROM dim_customer)
                 < (SELECT COUNT(*) FROM map_customer_id)
            THEN 'PASS' ELSE 'FAIL' END,
       'customer_unique_id grain must collapse below customer_id count';

-- ------------------------ REFERENTIAL --------------------------------

INSERT INTO data_quality_checks (check_name, severity, observed, expected, status, notes)
SELECT 'orphan_items_no_parent_order', 'FAIL', COUNT(*), '0',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       'staged order_items whose order_id is absent from fact_orders'
FROM stg_order_items i
LEFT JOIN fact_orders o ON o.order_id = i.order_id
WHERE o.order_id IS NULL;

INSERT INTO data_quality_checks (check_name, severity, observed, expected, status, notes)
SELECT 'orphan_reviews_no_parent_order', 'WARN', COUNT(*), '0',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       'reviews pointing at an order we did not load'
FROM stg_order_reviews r
LEFT JOIN fact_orders o ON o.order_id = r.order_id
WHERE o.order_id IS NULL;

INSERT INTO data_quality_checks (check_name, severity, observed, expected, status, notes)
SELECT 'items_with_unresolved_product', 'WARN', COUNT(*), '0',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       'line items whose product_id is missing from the product dimension'
FROM fact_order_items WHERE product_sk IS NULL;

-- ------------------------- UNIQUENESS --------------------------------

INSERT INTO data_quality_checks (check_name, severity, observed, expected, status, notes)
SELECT 'duplicate_order_ids_in_source', 'FAIL', COUNT(*), '0',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       'order_id must be unique in the raw file'
FROM (SELECT order_id FROM stg_orders GROUP BY order_id HAVING COUNT(*) > 1) d;

INSERT INTO data_quality_checks (check_name, severity, observed, expected, status, notes)
SELECT 'orders_with_multiple_reviews', 'INFO', COUNT(*), '~550',
       'PASS',
       'known source quirk; transform keeps the earliest review per order'
FROM (SELECT order_id FROM stg_order_reviews GROUP BY order_id HAVING COUNT(*) > 1) d;

-- -------------------------- VALIDITY ---------------------------------

INSERT INTO data_quality_checks (check_name, severity, observed, expected, status, notes)
SELECT 'negative_or_zero_prices', 'FAIL', COUNT(*), '0',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       'line item price must be positive'
FROM fact_order_items WHERE price <= 0;

INSERT INTO data_quality_checks (check_name, severity, observed, expected, status, notes)
SELECT 'delivered_before_purchased', 'FAIL', COUNT(*), '0',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       'time-travelling deliveries indicate a timestamp parse failure'
FROM fact_orders
WHERE delivered_customer_ts IS NOT NULL
  AND delivered_customer_ts < purchase_ts;

INSERT INTO data_quality_checks (check_name, severity, observed, expected, status, notes)
SELECT 'delivered_status_without_delivery_date', 'WARN', COUNT(*), '<= 20',
       CASE WHEN COUNT(*) <= 20 THEN 'PASS' ELSE 'FAIL' END,
       'status says delivered but no receipt timestamp exists'
FROM fact_orders
WHERE order_status = 'delivered' AND delivered_customer_ts IS NULL;

INSERT INTO data_quality_checks (check_name, severity, observed, expected, status, notes)
SELECT 'review_score_out_of_range', 'FAIL', COUNT(*), '0',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       'review_score must sit between 1 and 5'
FROM fact_orders
WHERE review_score IS NOT NULL AND review_score NOT BETWEEN 1 AND 5;

-- -------------------------- RECONCILIATION ---------------------------
-- Payments should approximately equal order value. They will not match
-- to the cent (vouchers, rounding), so this is a tolerance check, not
-- an equality check — and saying so out loud is the point.

INSERT INTO data_quality_checks (check_name, severity, observed, expected, status, notes)
SELECT 'payment_vs_order_value_mismatch_over_1pct', 'WARN', COUNT(*), '< 5% of orders',
       CASE WHEN COUNT(*) < (SELECT COUNT(*) * 0.05 FROM fact_orders)
            THEN 'PASS' ELSE 'FAIL' END,
       'sum(payments) vs sum(items+freight), 1% tolerance'
FROM fact_orders
WHERE payment_value IS NOT NULL AND order_value > 0
  AND ABS(payment_value - order_value) / order_value > 0.01;

-- ------------------------- TIMELINESS --------------------------------

INSERT INTO data_quality_checks (check_name, severity, observed, expected, status, notes)
SELECT 'orders_outside_dim_date_range', 'FAIL', COUNT(*), '0',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       'purchase dates with no matching dim_date row would break every join'
FROM fact_orders fo
LEFT JOIN dim_date d ON d.date_key = fo.purchase_date_key
WHERE d.date_key IS NULL;

-- ====================== THE ONE QUERY TO RUN =========================
SELECT status, severity, COUNT(*) AS checks
FROM data_quality_checks
WHERE run_ts >= NOW() - INTERVAL 5 MINUTE
GROUP BY status, severity
ORDER BY status, FIELD(severity, 'FAIL', 'WARN', 'INFO');

SELECT check_name, severity, observed, expected, status, notes
FROM data_quality_checks
WHERE run_ts >= NOW() - INTERVAL 5 MINUTE
ORDER BY FIELD(status,'FAIL','PASS'), FIELD(severity,'FAIL','WARN','INFO'), check_name;
