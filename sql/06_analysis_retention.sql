-- =====================================================================
-- 06_analysis_retention.sql
-- Q: Do Olist customers come back, and who is worth keeping?
-- Techniques: CTEs, conditional aggregation (manual pivot), NTILE,
--             PERIOD_DIFF, window frames.
-- =====================================================================

USE olist;

-- ---------------------------------------------------------------------
-- 6.1  Headline repeat rate
--      Run this at BOTH grains and put both numbers in your README. The
--      gap between them is the single best proof that you understood
--      the data model rather than copying a notebook.
-- ---------------------------------------------------------------------
SELECT
    'per customer_id (WRONG grain)' AS measured_at,
    COUNT(*)                                                       AS customers,
    SUM(CASE WHEN orders > 1 THEN 1 ELSE 0 END)                    AS repeaters,
    ROUND(100 * SUM(CASE WHEN orders > 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS repeat_pct
FROM (
    SELECT m.customer_id, COUNT(*) AS orders
    FROM fact_orders fo
    JOIN map_customer_id m ON m.customer_sk = fo.customer_sk
    GROUP BY m.customer_id
) a
UNION ALL
SELECT
    'per customer_unique_id (RIGHT grain)',
    COUNT(*),
    SUM(CASE WHEN orders > 1 THEN 1 ELSE 0 END),
    ROUND(100 * SUM(CASE WHEN orders > 1 THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM (
    SELECT customer_sk, COUNT(*) AS orders
    FROM fact_orders
    GROUP BY customer_sk
) b;

-- ---------------------------------------------------------------------
-- 6.2  Monthly cohort retention triangle
--      Rows = acquisition month. Columns = months since acquisition.
--      Cells = % of that cohort who ordered again in month N.
-- ---------------------------------------------------------------------
WITH first_order AS (
    SELECT customer_sk,
           MIN(purchase_ts) AS first_ts
    FROM fact_orders
    WHERE order_status <> 'canceled'
    GROUP BY customer_sk
),
cohort AS (
    SELECT f.customer_sk,
           EXTRACT(YEAR_MONTH FROM f.first_ts) AS cohort_ym
    FROM first_order f
),
activity AS (
    SELECT c.cohort_ym,
           c.customer_sk,
           PERIOD_DIFF(EXTRACT(YEAR_MONTH FROM o.purchase_ts), c.cohort_ym) AS month_index
    FROM fact_orders o
    JOIN cohort c ON c.customer_sk = o.customer_sk
    WHERE o.order_status <> 'canceled'
),
sized AS (
    SELECT cohort_ym, COUNT(DISTINCT customer_sk) AS cohort_size
    FROM activity WHERE month_index = 0
    GROUP BY cohort_ym
)
SELECT
    a.cohort_ym,
    s.cohort_size,
    ROUND(100 * COUNT(DISTINCT CASE WHEN a.month_index = 1 THEN a.customer_sk END) / s.cohort_size, 2) AS m1_pct,
    ROUND(100 * COUNT(DISTINCT CASE WHEN a.month_index = 2 THEN a.customer_sk END) / s.cohort_size, 2) AS m2_pct,
    ROUND(100 * COUNT(DISTINCT CASE WHEN a.month_index = 3 THEN a.customer_sk END) / s.cohort_size, 2) AS m3_pct,
    ROUND(100 * COUNT(DISTINCT CASE WHEN a.month_index = 6 THEN a.customer_sk END) / s.cohort_size, 2) AS m6_pct,
    ROUND(100 * COUNT(DISTINCT CASE WHEN a.month_index BETWEEN 1 AND 12 THEN a.customer_sk END) / s.cohort_size, 2) AS any_repeat_12m_pct
FROM activity a
JOIN sized s ON s.cohort_ym = a.cohort_ym
GROUP BY a.cohort_ym, s.cohort_size
HAVING s.cohort_size >= 30
ORDER BY a.cohort_ym;

-- ---------------------------------------------------------------------
-- 6.3  RFM segmentation
--      Recency measured against the last purchase in the dataset, not
--      NOW() — the snapshot ends in 2018, so NOW() would score every
--      customer as equally stale.
-- ---------------------------------------------------------------------
WITH asof AS (
    SELECT MAX(purchase_ts) AS snapshot_ts FROM fact_orders
),
base AS (
    SELECT
        fo.customer_sk,
        TIMESTAMPDIFF(DAY, MAX(fo.purchase_ts), (SELECT snapshot_ts FROM asof)) AS recency_days,
        COUNT(*)                AS frequency,
        SUM(fo.order_value)     AS monetary
    FROM fact_orders fo
    WHERE fo.order_status <> 'canceled'
    GROUP BY fo.customer_sk
),
scored AS (
    SELECT
        base.*,
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,  -- lower recency = better = 5
        NTILE(5) OVER (ORDER BY frequency ASC)     AS f_score,
        NTILE(5) OVER (ORDER BY monetary  ASC)     AS m_score
    FROM base
),
segmented AS (
    SELECT
        s.*,
        CASE
            WHEN r_score >= 4 AND f_score >= 4               THEN 'Champions'
            WHEN r_score >= 3 AND f_score >= 3               THEN 'Loyal'
            WHEN r_score >= 4 AND f_score <= 2               THEN 'New / Promising'
            WHEN r_score <= 2 AND f_score >= 3               THEN 'At Risk'
            WHEN r_score <= 2 AND m_score >= 4               THEN 'Cannot Lose Them'
            WHEN r_score <= 2                                THEN 'Hibernating'
            ELSE 'Needs Attention'
        END AS segment
    FROM scored s
)
SELECT
    segment,
    COUNT(*)                                     AS customers,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_base,
    ROUND(AVG(recency_days))                     AS avg_recency_days,
    ROUND(AVG(frequency), 2)                     AS avg_orders,
    ROUND(AVG(monetary), 2)                      AS avg_spend,
    ROUND(SUM(monetary), 2)                      AS total_spend,
    ROUND(100 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 2) AS pct_of_revenue
FROM segmented
GROUP BY segment
ORDER BY total_spend DESC;

-- ---------------------------------------------------------------------
-- 6.4  Time to second order — for the customers who DO come back,
--      how long is the window you have to win them?
-- ---------------------------------------------------------------------
WITH seq AS (
    SELECT customer_sk, customer_order_seq, purchase_ts
    FROM fact_orders
    WHERE customer_order_seq <= 2 AND order_status <> 'canceled'
),
gaps AS (
    SELECT
        customer_sk,
        TIMESTAMPDIFF(DAY,
            MIN(CASE WHEN customer_order_seq = 1 THEN purchase_ts END),
            MIN(CASE WHEN customer_order_seq = 2 THEN purchase_ts END)) AS days_to_second
    FROM seq
    GROUP BY customer_sk
    HAVING days_to_second IS NOT NULL
)
SELECT
    COUNT(*)                AS repeat_customers,
    MIN(days_to_second)     AS min_days,
    ROUND(AVG(days_to_second), 1) AS avg_days,
    MAX(days_to_second)     AS max_days,
    -- MySQL has no MEDIAN(). This is the standard row-number workaround.
    (SELECT ROUND(AVG(days_to_second), 1) FROM (
        SELECT days_to_second,
               ROW_NUMBER() OVER (ORDER BY days_to_second) AS rn,
               COUNT(*)     OVER ()                        AS cnt
        FROM gaps
     ) m WHERE rn IN (FLOOR((cnt + 1) / 2), CEIL((cnt + 1) / 2))) AS median_days
FROM gaps;
