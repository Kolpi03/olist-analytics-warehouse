-- =====================================================================
-- 08_analysis_revenue_sellers.sql
-- Q: Is growth real, which categories carry it, and which sellers are
--    dragging the marketplace down?
-- Techniques: LAG, running SUM window frames, RANK / PERCENT_RANK,
--             haversine distance, HAVING-based significance filters.
-- =====================================================================

USE olist;

-- ---------------------------------------------------------------------
-- 8.1  Monthly revenue, split new vs returning, with MoM growth
--      A marketplace can post rising revenue while its customer base
--      rots. Splitting on customer_order_seq is what exposes that.
-- ---------------------------------------------------------------------
WITH monthly AS (
    SELECT
        EXTRACT(YEAR_MONTH FROM purchase_ts) AS ym,
        SUM(order_value)                                                     AS revenue,
        SUM(CASE WHEN customer_order_seq = 1 THEN order_value ELSE 0 END)    AS new_cust_revenue,
        SUM(CASE WHEN customer_order_seq > 1 THEN order_value ELSE 0 END)    AS returning_revenue,
        COUNT(*)                                                             AS orders,
        COUNT(DISTINCT customer_sk)                                          AS active_customers
    FROM fact_orders
    WHERE order_status <> 'canceled' AND order_value > 0
    GROUP BY ym
)
SELECT
    ym,
    orders,
    active_customers,
    ROUND(revenue, 2)                                          AS revenue,
    ROUND(revenue / orders, 2)                                 AS aov,
    ROUND(100 * returning_revenue / revenue, 2)                AS pct_revenue_from_returning,
    ROUND(LAG(revenue) OVER (ORDER BY ym), 2)                  AS prev_month_revenue,
    ROUND(100 * (revenue - LAG(revenue) OVER (ORDER BY ym))
              / NULLIF(LAG(revenue) OVER (ORDER BY ym), 0), 2) AS mom_growth_pct
FROM monthly
ORDER BY ym;

-- ---------------------------------------------------------------------
-- 8.2  Category Pareto — how few categories carry 80% of revenue?
--      Running total with an explicit window frame.
-- ---------------------------------------------------------------------
WITH cat_rev AS (
    SELECT
        dp.category_en,
        SUM(foi.price)      AS revenue,
        COUNT(*)            AS items_sold,
        COUNT(DISTINCT foi.order_id) AS orders
    FROM fact_order_items foi
    JOIN dim_product dp ON dp.product_sk = foi.product_sk
    GROUP BY dp.category_en
),
ranked AS (
    SELECT
        cat_rev.*,
        ROW_NUMBER() OVER (ORDER BY revenue DESC) AS rnk,
        SUM(revenue) OVER (
            ORDER BY revenue DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS running_revenue,
        SUM(revenue) OVER () AS total_revenue
    FROM cat_rev
)
SELECT
    rnk,
    category_en,
    ROUND(revenue, 2)                                  AS revenue,
    items_sold,
    ROUND(100 * revenue / total_revenue, 2)            AS pct_of_revenue,
    ROUND(100 * running_revenue / total_revenue, 2)    AS cumulative_pct,
    CASE WHEN 100 * running_revenue / total_revenue <= 80 THEN 'core 80%' ELSE 'long tail' END AS pareto_band
FROM ranked
ORDER BY rnk;

-- ---------------------------------------------------------------------
-- 8.3  Seller scorecard
--      HAVING >= 30 orders is deliberate: without a volume floor the
--      "best" and "worst" sellers are all one-order accidents. Say this
--      out loud in the README — it is exactly the kind of judgement
--      call interviewers probe for.
-- ---------------------------------------------------------------------
WITH seller_stats AS (
    SELECT
        ds.seller_sk,
        ds.seller_id,
        ds.state,
        COUNT(DISTINCT foi.order_id)   AS orders,
        SUM(foi.price)                 AS revenue,
        AVG(fo.is_late)                AS late_rate,
        AVG(fo.review_score)           AS avg_review,
        AVG(fo.delivery_days)          AS avg_delivery_days
    FROM fact_order_items foi
    JOIN dim_seller  ds ON ds.seller_sk = foi.seller_sk
    JOIN fact_orders fo ON fo.order_id  = foi.order_id
    GROUP BY ds.seller_sk, ds.seller_id, ds.state
    HAVING orders >= 30
)
SELECT
    RANK()         OVER (ORDER BY revenue DESC)      AS revenue_rank,
    seller_id,
    state,
    orders,
    ROUND(revenue, 2)                                AS revenue,
    ROUND(100 * late_rate, 2)                        AS late_pct,
    ROUND(avg_review, 2)                             AS avg_review,
    ROUND(avg_delivery_days, 1)                      AS avg_delivery_days,
    ROUND(100 * PERCENT_RANK() OVER (ORDER BY late_rate), 1) AS late_percentile,
    CASE
        WHEN PERCENT_RANK() OVER (ORDER BY late_rate) >= 0.90 THEN 'ESCALATE'
        WHEN PERCENT_RANK() OVER (ORDER BY late_rate) >= 0.75 THEN 'WATCH'
        ELSE 'OK'
    END AS action
FROM seller_stats
ORDER BY late_pct DESC, revenue DESC
LIMIT 25;

-- How concentrated is the lateness problem?
WITH seller_stats AS (
    SELECT ds.seller_sk,
           COUNT(*)                                       AS items,
           SUM(CASE WHEN fo.is_late = 1 THEN 1 ELSE 0 END) AS late_items
    FROM fact_order_items foi
    JOIN dim_seller  ds ON ds.seller_sk = foi.seller_sk
    JOIN fact_orders fo ON fo.order_id  = foi.order_id
    WHERE fo.is_late IS NOT NULL
    GROUP BY ds.seller_sk
),
ranked AS (
    SELECT seller_sk, late_items,
           ROW_NUMBER() OVER (ORDER BY late_items DESC) AS rnk,
           SUM(late_items) OVER (ORDER BY late_items DESC
                                 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_late,
           SUM(late_items) OVER () AS total_late,
           COUNT(*)        OVER () AS total_sellers
    FROM seller_stats
)
SELECT
    MIN(rnk)                                     AS sellers_causing_half_of_late_deliveries,
    MAX(total_sellers)                           AS total_sellers,
    ROUND(100 * MIN(rnk) / MAX(total_sellers), 1) AS pct_of_sellers
FROM ranked
WHERE running_late >= total_late * 0.5;

-- ---------------------------------------------------------------------
-- 8.4  Freight pricing vs actual distance
--      Haversine between seller and customer zip centroids. If freight
--      is priced rationally, cost should climb with distance; where it
--      doesn't, Olist is subsidising some lanes and overcharging others.
-- ---------------------------------------------------------------------
WITH shipped AS (
    SELECT
        foi.order_id,
        foi.freight_value,
        foi.price,
        gc.lat AS c_lat, gc.lng AS c_lng,
        gs.lat AS s_lat, gs.lng AS s_lng
    FROM fact_order_items foi
    JOIN fact_orders   fo ON fo.order_id   = foi.order_id
    JOIN dim_customer  dc ON dc.customer_sk = fo.customer_sk
    JOIN dim_seller    ds ON ds.seller_sk   = foi.seller_sk
    JOIN dim_geography gc ON gc.zip_code_prefix = dc.zip_code_prefix
    JOIN dim_geography gs ON gs.zip_code_prefix = ds.zip_code_prefix
    WHERE foi.freight_value IS NOT NULL
),
dist AS (
    SELECT
        freight_value,
        price,
        6371 * 2 * ASIN(SQRT(
            POWER(SIN(RADIANS(c_lat - s_lat) / 2), 2) +
            COS(RADIANS(s_lat)) * COS(RADIANS(c_lat)) *
            POWER(SIN(RADIANS(c_lng - s_lng) / 2), 2)
        )) AS km
    FROM shipped
)
SELECT
    CASE
        WHEN km <  100 THEN 'a. under 100 km'
        WHEN km <  300 THEN 'b. 100-300 km'
        WHEN km <  700 THEN 'c. 300-700 km'
        WHEN km < 1500 THEN 'd. 700-1500 km'
        ELSE                'e. 1500+ km'
    END                                   AS distance_band,
    COUNT(*)                              AS shipments,
    ROUND(AVG(km), 1)                     AS avg_km,
    ROUND(AVG(freight_value), 2)          AS avg_freight,
    ROUND(AVG(freight_value / NULLIF(km, 0)), 4) AS freight_per_km,
    ROUND(100 * AVG(freight_value / NULLIF(price, 0)), 2) AS freight_as_pct_of_price
FROM dist
GROUP BY distance_band
ORDER BY distance_band;

-- ---------------------------------------------------------------------
-- 8.5  Payment behaviour — does instalment financing lift basket size?
-- ---------------------------------------------------------------------
SELECT
    fp.payment_type,
    COUNT(*)                                        AS payments,
    ROUND(AVG(fp.installments), 2)                  AS avg_installments,
    ROUND(AVG(fp.payment_value), 2)                 AS avg_payment,
    ROUND(SUM(fp.payment_value), 2)                 AS total_value,
    ROUND(100 * SUM(fp.payment_value) / SUM(SUM(fp.payment_value)) OVER (), 2) AS pct_of_gmv
FROM fact_payments fp
GROUP BY fp.payment_type
ORDER BY total_value DESC;
