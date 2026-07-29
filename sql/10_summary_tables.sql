-- =====================================================================
-- 10_summary_tables.sql
-- MySQL has no materialised views. This is how you get the same thing:
-- physical summary tables + a stored procedure that rebuilds them +
-- an event that runs the procedure on a schedule.
--
-- Why bother: your BI tool should hit a 500-row summary table, not
-- re-aggregate 112k line items on every dashboard filter change. This
-- is the difference between a dashboard that feels instant and one that
-- spins for eight seconds.
-- =====================================================================

USE olist;

-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS rpt_monthly_kpis;
CREATE TABLE rpt_monthly_kpis (
    year_month_key          INT PRIMARY KEY,
    orders                  INT,
    active_customers        INT,
    new_customers           INT,
    revenue                 DECIMAL(14,2),
    returning_revenue       DECIMAL(14,2),
    aov                     DECIMAL(10,2),
    avg_review              DECIMAL(4,2),
    late_pct                DECIMAL(5,2),
    avg_delivery_days       DECIMAL(6,2),
    refreshed_at            DATETIME
) ENGINE=InnoDB;

DROP TABLE IF EXISTS rpt_seller_scorecard;
CREATE TABLE rpt_seller_scorecard (
    seller_sk         INT PRIMARY KEY,
    seller_id         VARCHAR(64),
    state             VARCHAR(8),
    orders            INT,
    revenue           DECIMAL(14,2),
    late_pct          DECIMAL(5,2),
    avg_review        DECIMAL(4,2),
    avg_delivery_days DECIMAL(6,2),
    action_flag       VARCHAR(16),
    refreshed_at      DATETIME
) ENGINE=InnoDB;

DROP TABLE IF EXISTS rpt_category_performance;
CREATE TABLE rpt_category_performance (
    category_en    VARCHAR(128) PRIMARY KEY,
    items_sold     INT,
    orders         INT,
    revenue        DECIMAL(14,2),
    pct_of_revenue DECIMAL(6,2),
    avg_review     DECIMAL(4,2),
    late_pct       DECIMAL(5,2),
    refreshed_at   DATETIME
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_refresh_reporting;

DELIMITER $$

CREATE PROCEDURE sp_refresh_reporting()
BEGIN
    -- Roll the whole refresh back if any statement fails, so the BI
    -- layer never reads a half-rebuilt table.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        INSERT INTO data_quality_checks
            (check_name, severity, observed, expected, status, notes)
        VALUES ('sp_refresh_reporting', 'FAIL', NULL, 'completes',
                'FAIL', 'refresh aborted and rolled back');
        RESIGNAL;
    END;

    START TRANSACTION;

    -- ---- monthly KPIs ----
    DELETE FROM rpt_monthly_kpis;
    INSERT INTO rpt_monthly_kpis
    SELECT
        EXTRACT(YEAR_MONTH FROM purchase_ts),
        COUNT(*),
        COUNT(DISTINCT customer_sk),
        COUNT(DISTINCT CASE WHEN customer_order_seq = 1 THEN customer_sk END),
        ROUND(SUM(order_value), 2),
        ROUND(SUM(CASE WHEN customer_order_seq > 1 THEN order_value ELSE 0 END), 2),
        ROUND(SUM(order_value) / NULLIF(COUNT(*), 0), 2),
        ROUND(AVG(review_score), 2),
        ROUND(100 * AVG(is_late), 2),
        ROUND(AVG(delivery_days), 2),
        NOW()
    FROM fact_orders
    WHERE order_status <> 'canceled'
    GROUP BY EXTRACT(YEAR_MONTH FROM purchase_ts);

    -- ---- seller scorecard ----
    DELETE FROM rpt_seller_scorecard;
    INSERT INTO rpt_seller_scorecard
    SELECT
        s.seller_sk, s.seller_id, s.state, s.orders, s.revenue,
        s.late_pct, s.avg_review, s.avg_delivery_days,
        CASE
            WHEN s.late_pct >= 25 AND s.orders >= 30 THEN 'ESCALATE'
            WHEN s.late_pct >= 15 AND s.orders >= 30 THEN 'WATCH'
            ELSE 'OK'
        END,
        NOW()
    FROM (
        SELECT
            ds.seller_sk, ds.seller_id, ds.state,
            COUNT(DISTINCT foi.order_id)      AS orders,
            ROUND(SUM(foi.price), 2)          AS revenue,
            ROUND(100 * AVG(fo.is_late), 2)   AS late_pct,
            ROUND(AVG(fo.review_score), 2)    AS avg_review,
            ROUND(AVG(fo.delivery_days), 2)   AS avg_delivery_days
        FROM fact_order_items foi
        JOIN dim_seller  ds ON ds.seller_sk = foi.seller_sk
        JOIN fact_orders fo ON fo.order_id  = foi.order_id
        GROUP BY ds.seller_sk, ds.seller_id, ds.state
    ) s;

    -- ---- category performance ----
    DELETE FROM rpt_category_performance;
    INSERT INTO rpt_category_performance
    SELECT
        c.category_en, c.items_sold, c.orders, c.revenue,
        ROUND(100 * c.revenue / NULLIF(SUM(c.revenue) OVER (), 0), 2),
        c.avg_review, c.late_pct, NOW()
    FROM (
        SELECT
            dp.category_en,
            COUNT(*)                          AS items_sold,
            COUNT(DISTINCT foi.order_id)      AS orders,
            ROUND(SUM(foi.price), 2)          AS revenue,
            ROUND(AVG(fo.review_score), 2)    AS avg_review,
            ROUND(100 * AVG(fo.is_late), 2)   AS late_pct
        FROM fact_order_items foi
        JOIN dim_product dp ON dp.product_sk = foi.product_sk
        JOIN fact_orders fo ON fo.order_id   = foi.order_id
        GROUP BY dp.category_en
    ) c;

    COMMIT;

    INSERT INTO data_quality_checks
        (check_name, severity, observed, expected, status, notes)
    VALUES ('sp_refresh_reporting', 'INFO',
            (SELECT COUNT(*) FROM rpt_monthly_kpis), '> 0',
            'PASS', 'reporting layer rebuilt');
END$$

DELIMITER ;

-- ---------------------------------------------------------------------
-- Schedule it. The event scheduler is OFF by default in MySQL.
-- ---------------------------------------------------------------------
SET GLOBAL event_scheduler = ON;

DROP EVENT IF EXISTS ev_nightly_refresh;

CREATE EVENT ev_nightly_refresh
ON SCHEDULE EVERY 1 DAY
STARTS (CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 2 HOUR)
DO CALL sp_refresh_reporting();

-- Run it once now so the tables are populated immediately.
CALL sp_refresh_reporting();

SELECT * FROM rpt_monthly_kpis ORDER BY year_month_key;
SELECT action_flag, COUNT(*) AS sellers FROM rpt_seller_scorecard GROUP BY action_flag;
