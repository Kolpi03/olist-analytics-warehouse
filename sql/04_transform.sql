-- =====================================================================
-- 04_transform.sql
-- Staging (all text) -> typed star schema.
-- Idempotent: safe to re-run. Every load starts by truncating targets,
-- so re-running never double-counts. (The Zepto-style
-- "UPDATE price = price/100" pattern is NOT idempotent — run it twice
-- and every price is wrong. Never write a transform you can't re-run.)
-- =====================================================================

USE olist;

SET SESSION cte_max_recursion_depth = 20000;
SET FOREIGN_KEY_CHECKS = 0;

TRUNCATE TABLE fact_payments;
TRUNCATE TABLE fact_order_items;
TRUNCATE TABLE fact_orders;
TRUNCATE TABLE map_customer_id;
TRUNCATE TABLE dim_customer;
TRUNCATE TABLE dim_seller;
TRUNCATE TABLE dim_product;
TRUNCATE TABLE dim_geography;
TRUNCATE TABLE dim_date;

SET FOREIGN_KEY_CHECKS = 1;

-- ---------------------------------------------------------------------
-- 1. dim_date  (generated, not sourced — recursive CTE, MySQL 8 only)
-- ---------------------------------------------------------------------
INSERT INTO dim_date
WITH RECURSIVE d AS (
    SELECT DATE('2016-01-01') AS dt
    UNION ALL
    SELECT dt + INTERVAL 1 DAY FROM d WHERE dt < '2019-12-31'
)
SELECT
    CAST(DATE_FORMAT(dt, '%Y%m%d') AS UNSIGNED)          AS date_key,
    dt                                                    AS full_date,
    YEAR(dt), QUARTER(dt), MONTH(dt), MONTHNAME(dt),
    DATE_FORMAT(dt, '%Y-%m-01')                           AS month_start,
    CAST(DATE_FORMAT(dt, '%Y%m') AS UNSIGNED)             AS year_month_key,
    DAYOFMONTH(dt), DAYOFWEEK(dt), DAYNAME(dt),
    CASE WHEN DAYOFWEEK(dt) IN (1,7) THEN 1 ELSE 0 END    AS is_weekend
FROM d;

-- ---------------------------------------------------------------------
-- 2. dim_geography  (~1M raw points -> one centroid per zip prefix)
--    Brazil spans roughly lat -34..5, lng -74..-34. Points outside that
--    box are bad geocodes and are excluded from the centroid.
-- ---------------------------------------------------------------------
INSERT INTO dim_geography (zip_code_prefix, lat, lng, city, state)
SELECT
    g.geolocation_zip_code_prefix,
    ROUND(AVG(CAST(g.geolocation_lat AS DECIMAL(10,6))), 6),
    ROUND(AVG(CAST(g.geolocation_lng AS DECIMAL(10,6))), 6),
    MIN(g.geolocation_city),
    MIN(g.geolocation_state)
FROM stg_geolocation g
WHERE CAST(g.geolocation_lat AS DECIMAL(10,6)) BETWEEN -34 AND  6
  AND CAST(g.geolocation_lng AS DECIMAL(10,6)) BETWEEN -74 AND -34
GROUP BY g.geolocation_zip_code_prefix;

-- ---------------------------------------------------------------------
-- 3. dim_customer  (grain = the PERSON, not the order)
--    A person can appear with several zip codes across orders; we keep
--    the one from their most frequently seen location.
-- ---------------------------------------------------------------------
INSERT INTO dim_customer (customer_unique_id, zip_code_prefix, city, state)
SELECT customer_unique_id, zip_code_prefix, city, state
FROM (
    SELECT
        c.customer_unique_id,
        c.customer_zip_code_prefix AS zip_code_prefix,
        c.customer_city           AS city,
        c.customer_state          AS state,
        ROW_NUMBER() OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY COUNT(*) DESC, c.customer_zip_code_prefix
        ) AS rn
    FROM stg_customers c
    GROUP BY c.customer_unique_id, c.customer_zip_code_prefix,
             c.customer_city, c.customer_state
) t
WHERE rn = 1;

INSERT INTO map_customer_id (customer_id, customer_sk)
SELECT c.customer_id, dc.customer_sk
FROM stg_customers c
JOIN dim_customer dc ON dc.customer_unique_id = c.customer_unique_id;

-- ---------------------------------------------------------------------
-- 4. dim_seller
-- ---------------------------------------------------------------------
INSERT INTO dim_seller (seller_id, zip_code_prefix, city, state)
SELECT seller_id, seller_zip_code_prefix, seller_city, seller_state
FROM stg_sellers;

-- ---------------------------------------------------------------------
-- 5. dim_product
--    ~610 products have no category in the source. We label them
--    'unknown' rather than dropping them: they still carry revenue, and
--    silently losing revenue rows is the classic way an analyst's totals
--    stop reconciling with finance's.
-- ---------------------------------------------------------------------
INSERT INTO dim_product (product_id, category_pt, category_en, weight_g,
                         length_cm, height_cm, width_cm, volume_cm3, photos_qty)
SELECT
    p.product_id,
    COALESCE(NULLIF(p.product_category_name, ''), 'unknown'),
    COALESCE(NULLIF(t.product_category_name_english, ''), 'unknown'),
    CAST(NULLIF(p.product_weight_g, '')  AS SIGNED),
    CAST(NULLIF(p.product_length_cm, '') AS SIGNED),
    CAST(NULLIF(p.product_height_cm, '') AS SIGNED),
    CAST(NULLIF(p.product_width_cm, '')  AS SIGNED),
    CAST(NULLIF(p.product_length_cm, '') AS SIGNED)
      * CAST(NULLIF(p.product_height_cm, '') AS SIGNED)
      * CAST(NULLIF(p.product_width_cm, '')  AS SIGNED),
    CAST(NULLIF(p.product_photos_qty, '') AS SIGNED)
FROM stg_products p
LEFT JOIN stg_category_translation t
       ON t.product_category_name = p.product_category_name;

-- ---------------------------------------------------------------------
-- 6. fact_orders  (base columns)
-- ---------------------------------------------------------------------
INSERT INTO fact_orders (
    order_id, customer_sk, purchase_date_key, order_status,
    purchase_ts, approved_ts, delivered_carrier_ts,
    delivered_customer_ts, estimated_delivery_ts
)
SELECT
    o.order_id,
    m.customer_sk,
    CAST(DATE_FORMAT(STR_TO_DATE(o.order_purchase_timestamp, '%Y-%m-%d %H:%i:%s'), '%Y%m%d') AS UNSIGNED),
    o.order_status,
    STR_TO_DATE(NULLIF(o.order_purchase_timestamp, ''),      '%Y-%m-%d %H:%i:%s'),
    STR_TO_DATE(NULLIF(o.order_approved_at, ''),             '%Y-%m-%d %H:%i:%s'),
    STR_TO_DATE(NULLIF(o.order_delivered_carrier_date, ''),  '%Y-%m-%d %H:%i:%s'),
    STR_TO_DATE(NULLIF(o.order_delivered_customer_date, ''), '%Y-%m-%d %H:%i:%s'),
    STR_TO_DATE(NULLIF(o.order_estimated_delivery_date, ''), '%Y-%m-%d %H:%i:%s')
FROM stg_orders o
JOIN map_customer_id m ON m.customer_id = o.customer_id;

-- Derived delivery measures.
-- delay_days > 0 means the order arrived AFTER the promised date.
UPDATE fact_orders
SET delivery_days = TIMESTAMPDIFF(DAY, purchase_ts, delivered_customer_ts),
    promised_days = TIMESTAMPDIFF(DAY, purchase_ts, estimated_delivery_ts),
    delay_days    = TIMESTAMPDIFF(DAY, estimated_delivery_ts, delivered_customer_ts),
    is_late       = CASE
                        WHEN delivered_customer_ts IS NULL THEN NULL
                        WHEN delivered_customer_ts > estimated_delivery_ts THEN 1
                        ELSE 0
                    END;

-- ---------------------------------------------------------------------
-- 7. fact_order_items
--    Orphan guard: order_items referencing a missing order are skipped
--    by the inner join, and 05_data_quality.sql counts them.
-- ---------------------------------------------------------------------
INSERT INTO fact_order_items (order_id, order_item_id, product_sk, seller_sk,
                              purchase_date_key, price, freight_value, line_total)
SELECT
    i.order_id,
    CAST(i.order_item_id AS SIGNED),
    dp.product_sk,
    ds.seller_sk,
    fo.purchase_date_key,
    CAST(NULLIF(i.price, '')         AS DECIMAL(10,2)),
    CAST(NULLIF(i.freight_value, '') AS DECIMAL(10,2)),
    CAST(NULLIF(i.price, '') AS DECIMAL(10,2))
      + COALESCE(CAST(NULLIF(i.freight_value, '') AS DECIMAL(10,2)), 0)
FROM stg_order_items i
JOIN fact_orders fo ON fo.order_id  = i.order_id
LEFT JOIN dim_product dp ON dp.product_id = i.product_id
LEFT JOIN dim_seller  ds ON ds.seller_id  = i.seller_id;

-- ---------------------------------------------------------------------
-- 8. fact_payments
-- ---------------------------------------------------------------------
INSERT INTO fact_payments (order_id, payment_sequential, payment_type,
                           installments, payment_value)
SELECT
    p.order_id,
    CAST(NULLIF(p.payment_sequential, '')   AS SIGNED),
    p.payment_type,
    CAST(NULLIF(p.payment_installments, '') AS SIGNED),
    CAST(NULLIF(p.payment_value, '')        AS DECIMAL(10,2))
FROM stg_order_payments p
JOIN fact_orders fo ON fo.order_id = p.order_id;

-- ---------------------------------------------------------------------
-- 9. Roll item / payment / review measures up onto fact_orders
-- ---------------------------------------------------------------------
UPDATE fact_orders fo
JOIN (
    SELECT order_id,
           COUNT(*)                  AS item_count,
           SUM(price)                AS product_revenue,
           SUM(freight_value)        AS freight_revenue,
           SUM(line_total)           AS order_value
    FROM fact_order_items
    GROUP BY order_id
) i ON i.order_id = fo.order_id
SET fo.item_count      = i.item_count,
    fo.product_revenue = i.product_revenue,
    fo.freight_revenue = i.freight_revenue,
    fo.order_value     = i.order_value;

UPDATE fact_orders fo
JOIN (
    SELECT order_id,
           SUM(payment_value) AS payment_value,
           MAX(installments)  AS max_installments
    FROM fact_payments
    GROUP BY order_id
) p ON p.order_id = fo.order_id
SET fo.payment_value    = p.payment_value,
    fo.max_installments = p.max_installments;

-- An order can carry more than one review row. Keep the earliest.
UPDATE fact_orders fo
JOIN (
    SELECT order_id, review_score
    FROM (
        SELECT r.order_id,
               CAST(r.review_score AS SIGNED) AS review_score,
               ROW_NUMBER() OVER (
                   PARTITION BY r.order_id
                   ORDER BY STR_TO_DATE(r.review_creation_date, '%Y-%m-%d %H:%i:%s'),
                            r.review_id
               ) AS rn
        FROM stg_order_reviews r
    ) x
    WHERE rn = 1
) rv ON rv.order_id = fo.order_id
SET fo.review_score = rv.review_score;

-- ---------------------------------------------------------------------
-- 10. customer_order_seq — 1 for a person's first order, 2 for their
--     second, and so on. This single column makes every "new vs
--     returning" split downstream a one-line filter.
-- ---------------------------------------------------------------------
UPDATE fact_orders fo
JOIN (
    SELECT order_id,
           ROW_NUMBER() OVER (
               PARTITION BY customer_sk
               ORDER BY purchase_ts, order_id
           ) AS seq
    FROM fact_orders
) s ON s.order_id = fo.order_id
SET fo.customer_order_seq = s.seq;

-- ---------------------------------------------------------------------
SELECT 'dim_date' t, COUNT(*) n FROM dim_date
UNION ALL SELECT 'dim_geography',    COUNT(*) FROM dim_geography
UNION ALL SELECT 'dim_customer',     COUNT(*) FROM dim_customer
UNION ALL SELECT 'map_customer_id',  COUNT(*) FROM map_customer_id
UNION ALL SELECT 'dim_seller',       COUNT(*) FROM dim_seller
UNION ALL SELECT 'dim_product',      COUNT(*) FROM dim_product
UNION ALL SELECT 'fact_orders',      COUNT(*) FROM fact_orders
UNION ALL SELECT 'fact_order_items', COUNT(*) FROM fact_order_items
UNION ALL SELECT 'fact_payments',    COUNT(*) FROM fact_payments;
