-- =====================================================================
-- 07_analysis_delivery.sql
-- THE HEADLINE. Three queries that form one causal chain:
--     late delivery  ->  bad review  ->  customer never returns
-- and a fourth that puts a rupee/real figure on it.
--
-- This is the section an interviewer will actually ask about, so every
-- query below answers a question a business person would ask out loud.
-- =====================================================================

USE olist;

-- ---------------------------------------------------------------------
-- 7.1  Order fulfilment funnel
--      Where do orders stop, and how long does each stage take?
--      MySQL has no MEDIAN(), so the p50 is done with the row-number
--      trick; the p90 uses the same frame.
-- ---------------------------------------------------------------------
WITH stages AS (
    SELECT
        order_id,
        TIMESTAMPDIFF(HOUR, purchase_ts,          approved_ts)           AS hrs_to_approve,
        TIMESTAMPDIFF(HOUR, approved_ts,          delivered_carrier_ts)  AS hrs_to_carrier,
        TIMESTAMPDIFF(HOUR, delivered_carrier_ts, delivered_customer_ts) AS hrs_to_customer
    FROM fact_orders
)
SELECT 'purchase -> approved'  AS stage,
       COUNT(hrs_to_approve)   AS orders_reaching_stage,
       ROUND(AVG(hrs_to_approve), 1) AS avg_hours
FROM stages
UNION ALL
SELECT 'approved -> carrier',  COUNT(hrs_to_carrier),  ROUND(AVG(hrs_to_carrier), 1)  FROM stages
UNION ALL
SELECT 'carrier -> customer',  COUNT(hrs_to_customer), ROUND(AVG(hrs_to_customer), 1) FROM stages;

-- Drop-off by status
SELECT
    order_status,
    COUNT(*)                                           AS orders,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)   AS pct_of_all
FROM fact_orders
GROUP BY order_status
ORDER BY orders DESC;

-- ---------------------------------------------------------------------
-- 7.2  LINK 1 — lateness destroys review scores
--      delay_days > 0 means the parcel arrived after the promised date.
-- ---------------------------------------------------------------------
SELECT
    CASE
        WHEN delay_days <= -10 THEN 'a. 10+ days early'
        WHEN delay_days <   -3 THEN 'b. 4-9 days early'
        WHEN delay_days <=   0 THEN 'c. on time (0-3 early)'
        WHEN delay_days <=   3 THEN 'd. 1-3 days late'
        WHEN delay_days <=   7 THEN 'e. 4-7 days late'
        WHEN delay_days <=  14 THEN 'f. 8-14 days late'
        ELSE                        'g. 15+ days late'
    END                                                            AS delivery_bucket,
    COUNT(*)                                                       AS orders,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)               AS pct_of_delivered,
    ROUND(AVG(review_score), 2)                                    AS avg_review,
    ROUND(100 * AVG(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END), 2) AS pct_1_2_star,
    ROUND(100 * AVG(CASE WHEN review_score  = 5 THEN 1 ELSE 0 END), 2) AS pct_5_star
FROM fact_orders
WHERE delivered_customer_ts IS NOT NULL
  AND review_score IS NOT NULL
GROUP BY delivery_bucket
ORDER BY delivery_bucket;

-- ---------------------------------------------------------------------
-- 7.3  LINK 2 — a bad review predicts churn
--      Take every customer's FIRST order, look at the review they left,
--      and measure whether they ever ordered again.
-- ---------------------------------------------------------------------
WITH first_orders AS (
    SELECT customer_sk, order_id, review_score, is_late, order_value
    FROM fact_orders
    WHERE customer_order_seq = 1
      AND review_score IS NOT NULL
),
returned AS (
    SELECT DISTINCT customer_sk
    FROM fact_orders
    WHERE customer_order_seq >= 2
)
SELECT
    f.review_score                                                     AS first_order_review,
    COUNT(*)                                                           AS customers,
    SUM(CASE WHEN r.customer_sk IS NOT NULL THEN 1 ELSE 0 END)         AS came_back,
    ROUND(100 * AVG(CASE WHEN r.customer_sk IS NOT NULL THEN 1 ELSE 0 END), 2) AS repeat_rate_pct
FROM first_orders f
LEFT JOIN returned r ON r.customer_sk = f.customer_sk
GROUP BY f.review_score
ORDER BY f.review_score;

-- ---------------------------------------------------------------------
-- 7.4  LINK 3 — collapse the chain: lateness -> repeat rate directly
-- ---------------------------------------------------------------------
WITH first_orders AS (
    SELECT customer_sk, is_late, order_value
    FROM fact_orders
    WHERE customer_order_seq = 1 AND is_late IS NOT NULL
),
returned AS (
    SELECT DISTINCT customer_sk FROM fact_orders WHERE customer_order_seq >= 2
)
SELECT
    CASE f.is_late WHEN 1 THEN 'first order LATE' ELSE 'first order on time' END AS experience,
    COUNT(*)                                                            AS customers,
    ROUND(100 * AVG(CASE WHEN r.customer_sk IS NOT NULL THEN 1 ELSE 0 END), 2) AS repeat_rate_pct,
    ROUND(AVG(f.order_value), 2)                                        AS avg_first_order_value
FROM first_orders f
LEFT JOIN returned r ON r.customer_sk = f.customer_sk
GROUP BY f.is_late;

-- ---------------------------------------------------------------------
-- 7.5  SIZE THE PRIZE
--      If late first-orders had converted to repeat customers at the
--      same rate as on-time ones, how much extra revenue would exist?
--
--      Stated as an estimate with its assumption on the label, because
--      that is how you present a number you cannot prove causally.
-- ---------------------------------------------------------------------
WITH first_orders AS (
    SELECT customer_sk, is_late FROM fact_orders
    WHERE customer_order_seq = 1 AND is_late IS NOT NULL
),
returned AS (
    SELECT DISTINCT customer_sk FROM fact_orders WHERE customer_order_seq >= 2
),
rates AS (
    SELECT
        f.is_late,
        COUNT(*) AS customers,
        AVG(CASE WHEN r.customer_sk IS NOT NULL THEN 1 ELSE 0 END) AS repeat_rate
    FROM first_orders f
    LEFT JOIN returned r ON r.customer_sk = f.customer_sk
    GROUP BY f.is_late
),
aov AS (
    SELECT AVG(order_value) AS avg_repeat_order_value
    FROM fact_orders WHERE customer_order_seq >= 2
)
SELECT
    (SELECT customers   FROM rates WHERE is_late = 1)                       AS late_first_customers,
    ROUND(100 * (SELECT repeat_rate FROM rates WHERE is_late = 0), 2)       AS ontime_repeat_pct,
    ROUND(100 * (SELECT repeat_rate FROM rates WHERE is_late = 1), 2)       AS late_repeat_pct,
    ROUND(
        (SELECT customers FROM rates WHERE is_late = 1)
      * ((SELECT repeat_rate FROM rates WHERE is_late = 0)
       - (SELECT repeat_rate FROM rates WHERE is_late = 1))
      * (SELECT avg_repeat_order_value FROM aov)
    , 2) AS estimated_recoverable_revenue_brl;

-- ---------------------------------------------------------------------
-- 7.6  WHERE is it going wrong? Lateness by customer state.
--      Tells you whether this is a carrier problem, a distance problem,
--      or a promise-setting problem.
-- ---------------------------------------------------------------------
SELECT
    dc.state,
    COUNT(*)                                       AS delivered_orders,
    ROUND(AVG(fo.delivery_days), 1)                AS avg_days_to_deliver,
    ROUND(AVG(fo.promised_days), 1)                AS avg_days_promised,
    ROUND(100 * AVG(fo.is_late), 2)                AS late_pct,
    ROUND(AVG(fo.review_score), 2)                 AS avg_review
FROM fact_orders fo
JOIN dim_customer dc ON dc.customer_sk = fo.customer_sk
WHERE fo.is_late IS NOT NULL
GROUP BY dc.state
HAVING delivered_orders >= 50
ORDER BY late_pct DESC;
