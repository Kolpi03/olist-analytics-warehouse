-- =====================================================================
-- 03_create_warehouse.sql
-- Star schema: 5 dimensions, 3 facts.
--
-- THE MOST IMPORTANT DESIGN DECISION IN THIS PROJECT
-- --------------------------------------------------
-- Olist has two customer keys:
--   customer_id        -> issued fresh for EVERY order (99,441 values)
--   customer_unique_id -> the actual human being      (96,096 values)
--
-- Almost every public notebook on this dataset joins on customer_id and
-- concludes "Olist has ~0% repeat customers." That is an artefact of the
-- key, not a fact about the business. dim_customer is therefore built at
-- customer_unique_id grain, and map_customer_id resolves the per-order
-- key onto it. Retention numbers only mean anything with this in place.
-- =====================================================================

USE olist;

-- =====================  DIMENSIONS  ==================================

DROP TABLE IF EXISTS dim_date;
CREATE TABLE dim_date (
    date_key      INT          NOT NULL PRIMARY KEY,   -- YYYYMMDD
    full_date     DATE         NOT NULL,
    year          SMALLINT     NOT NULL,
    quarter       TINYINT      NOT NULL,
    month         TINYINT      NOT NULL,
    month_name    VARCHAR(12)  NOT NULL,
    month_start   DATE         NOT NULL,
    year_month_key INT         NOT NULL,               -- YYYYMM, for PERIOD_DIFF (YEAR_MONTH is a reserved word)
    day_of_month  TINYINT      NOT NULL,
    day_of_week   TINYINT      NOT NULL,
    day_name      VARCHAR(12)  NOT NULL,
    is_weekend    TINYINT(1)   NOT NULL,
    UNIQUE KEY uk_full_date (full_date),
    KEY ix_year_month (year_month_key)
) ENGINE=InnoDB;

DROP TABLE IF EXISTS dim_customer;
CREATE TABLE dim_customer (
    customer_sk        INT AUTO_INCREMENT PRIMARY KEY,
    customer_unique_id VARCHAR(64) NOT NULL,
    zip_code_prefix    VARCHAR(16),
    city               VARCHAR(128),
    state              VARCHAR(8),
    UNIQUE KEY uk_customer_unique_id (customer_unique_id),
    KEY ix_cust_state (state)
) ENGINE=InnoDB;

-- Resolves the per-order customer_id onto the real person.
DROP TABLE IF EXISTS map_customer_id;
CREATE TABLE map_customer_id (
    customer_id VARCHAR(64) NOT NULL PRIMARY KEY,
    customer_sk INT         NOT NULL,
    KEY ix_map_sk (customer_sk)
) ENGINE=InnoDB;

DROP TABLE IF EXISTS dim_seller;
CREATE TABLE dim_seller (
    seller_sk       INT AUTO_INCREMENT PRIMARY KEY,
    seller_id       VARCHAR(64) NOT NULL,
    zip_code_prefix VARCHAR(16),
    city            VARCHAR(128),
    state           VARCHAR(8),
    UNIQUE KEY uk_seller_id (seller_id),
    KEY ix_seller_state (state)
) ENGINE=InnoDB;

DROP TABLE IF EXISTS dim_product;
CREATE TABLE dim_product (
    product_sk       INT AUTO_INCREMENT PRIMARY KEY,
    product_id       VARCHAR(64) NOT NULL,
    category_pt      VARCHAR(128),
    category_en      VARCHAR(128),
    weight_g         INT,
    length_cm        INT,
    height_cm        INT,
    width_cm         INT,
    volume_cm3       INT,
    photos_qty       INT,
    UNIQUE KEY uk_product_id (product_id),
    KEY ix_category_en (category_en)
) ENGINE=InnoDB;

-- One row per zip prefix. The raw geolocation table has ~1M rows because
-- it stores every observed lat/lng point; we collapse to the centroid.
DROP TABLE IF EXISTS dim_geography;
CREATE TABLE dim_geography (
    zip_code_prefix VARCHAR(16) NOT NULL PRIMARY KEY,
    lat             DECIMAL(10,6),
    lng             DECIMAL(10,6),
    city            VARCHAR(128),
    state           VARCHAR(8)
) ENGINE=InnoDB;

-- =====================  FACTS  =======================================

-- Grain: one row per order.
DROP TABLE IF EXISTS fact_orders;
CREATE TABLE fact_orders (
    order_id               VARCHAR(64) NOT NULL PRIMARY KEY,
    customer_sk            INT         NOT NULL,
    purchase_date_key      INT,
    order_status           VARCHAR(32),
    purchase_ts            DATETIME,
    approved_ts            DATETIME,
    delivered_carrier_ts   DATETIME,
    delivered_customer_ts  DATETIME,
    estimated_delivery_ts  DATETIME,

    -- Derived measures, materialised so the analysis queries stay readable
    -- and so they can be indexed.
    delivery_days          INT,          -- purchase -> customer receipt
    promised_days          INT,          -- purchase -> estimated date
    delay_days             INT,          -- actual - estimated; >0 means LATE
    is_late                TINYINT(1),
    item_count             INT     NOT NULL DEFAULT 0,
    product_revenue        DECIMAL(12,2) NOT NULL DEFAULT 0,
    freight_revenue        DECIMAL(12,2) NOT NULL DEFAULT 0,
    order_value            DECIMAL(12,2) NOT NULL DEFAULT 0,
    payment_value          DECIMAL(12,2),
    max_installments       INT,
    review_score           TINYINT,
    customer_order_seq     INT,          -- 1 = first ever order for this person

    KEY ix_fo_customer   (customer_sk),
    KEY ix_fo_datekey    (purchase_date_key),
    KEY ix_fo_status     (order_status),
    CONSTRAINT fk_fo_customer FOREIGN KEY (customer_sk) REFERENCES dim_customer(customer_sk)
) ENGINE=InnoDB;

-- Grain: one row per line item on an order.
DROP TABLE IF EXISTS fact_order_items;
CREATE TABLE fact_order_items (
    order_item_sk    BIGINT AUTO_INCREMENT PRIMARY KEY,
    order_id         VARCHAR(64) NOT NULL,
    order_item_id    INT         NOT NULL,
    product_sk       INT,
    seller_sk        INT,
    purchase_date_key INT,
    price            DECIMAL(10,2),
    freight_value    DECIMAL(10,2),
    line_total       DECIMAL(10,2),
    UNIQUE KEY uk_order_item (order_id, order_item_id),
    KEY ix_foi_product (product_sk),
    KEY ix_foi_seller  (seller_sk),
    KEY ix_foi_date    (purchase_date_key),
    CONSTRAINT fk_foi_order   FOREIGN KEY (order_id)   REFERENCES fact_orders(order_id),
    CONSTRAINT fk_foi_product FOREIGN KEY (product_sk) REFERENCES dim_product(product_sk),
    CONSTRAINT fk_foi_seller  FOREIGN KEY (seller_sk)  REFERENCES dim_seller(seller_sk)
) ENGINE=InnoDB;

-- Grain: one row per payment leg (an order can be split across methods).
DROP TABLE IF EXISTS fact_payments;
CREATE TABLE fact_payments (
    payment_sk         BIGINT AUTO_INCREMENT PRIMARY KEY,
    order_id           VARCHAR(64) NOT NULL,
    payment_sequential INT,
    payment_type       VARCHAR(32),
    installments       INT,
    payment_value      DECIMAL(10,2),
    KEY ix_fp_order (order_id),
    KEY ix_fp_type  (payment_type),
    CONSTRAINT fk_fp_order FOREIGN KEY (order_id) REFERENCES fact_orders(order_id)
) ENGINE=InnoDB;

-- Audit trail for the data quality suite.
DROP TABLE IF EXISTS data_quality_checks;
CREATE TABLE data_quality_checks (
    check_id     INT AUTO_INCREMENT PRIMARY KEY,
    run_ts       DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    check_name   VARCHAR(128) NOT NULL,
    severity     ENUM('INFO','WARN','FAIL') NOT NULL,
    observed     BIGINT,
    expected     VARCHAR(64),
    status       ENUM('PASS','FAIL') NOT NULL,
    notes        VARCHAR(512)
) ENGINE=InnoDB;
