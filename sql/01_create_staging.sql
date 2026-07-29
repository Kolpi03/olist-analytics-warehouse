-- =====================================================================
-- 01_create_staging.sql
-- Raw landing zone. Every column is VARCHAR/TEXT on purpose.
--
-- Design note: typed columns on a bulk import mean one malformed row
-- aborts the whole load (or, worse, silently coerces to 0 / 1970-01-01).
-- We land everything as text, then cast during the transform step where
-- failures are visible and recoverable.
-- =====================================================================

DROP DATABASE IF EXISTS olist;
CREATE DATABASE olist
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;
USE olist;

-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS stg_customers;
CREATE TABLE stg_customers (
    customer_id                VARCHAR(64),
    customer_unique_id         VARCHAR(64),
    customer_zip_code_prefix   VARCHAR(16),
    customer_city              VARCHAR(128),
    customer_state             VARCHAR(8)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS stg_geolocation;
CREATE TABLE stg_geolocation (
    geolocation_zip_code_prefix VARCHAR(16),
    geolocation_lat             VARCHAR(32),
    geolocation_lng             VARCHAR(32),
    geolocation_city            VARCHAR(128),
    geolocation_state           VARCHAR(8)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS stg_orders;
CREATE TABLE stg_orders (
    order_id                      VARCHAR(64),
    customer_id                   VARCHAR(64),
    order_status                  VARCHAR(32),
    order_purchase_timestamp      VARCHAR(32),
    order_approved_at             VARCHAR(32),
    order_delivered_carrier_date  VARCHAR(32),
    order_delivered_customer_date VARCHAR(32),
    order_estimated_delivery_date VARCHAR(32)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS stg_order_items;
CREATE TABLE stg_order_items (
    order_id            VARCHAR(64),
    order_item_id       VARCHAR(16),
    product_id          VARCHAR(64),
    seller_id           VARCHAR(64),
    shipping_limit_date VARCHAR(32),
    price               VARCHAR(32),
    freight_value       VARCHAR(32)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS stg_order_payments;
CREATE TABLE stg_order_payments (
    order_id             VARCHAR(64),
    payment_sequential   VARCHAR(16),
    payment_type         VARCHAR(32),
    payment_installments VARCHAR(16),
    payment_value        VARCHAR(32)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Free-text comment columns are dropped by scripts/prep_csvs.py.
DROP TABLE IF EXISTS stg_order_reviews;
CREATE TABLE stg_order_reviews (
    review_id               VARCHAR(64),
    order_id                VARCHAR(64),
    review_score            VARCHAR(8),
    review_creation_date    VARCHAR(32),
    review_answer_timestamp VARCHAR(32)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- NOTE: 'lenght' is misspelled in the source data. Do not "fix" it here,
-- or LOAD DATA column mapping will silently misalign.
DROP TABLE IF EXISTS stg_products;
CREATE TABLE stg_products (
    product_id                 VARCHAR(64),
    product_category_name      VARCHAR(128),
    product_name_lenght        VARCHAR(16),
    product_description_lenght VARCHAR(16),
    product_photos_qty         VARCHAR(16),
    product_weight_g           VARCHAR(16),
    product_length_cm          VARCHAR(16),
    product_height_cm          VARCHAR(16),
    product_width_cm           VARCHAR(16)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS stg_sellers;
CREATE TABLE stg_sellers (
    seller_id              VARCHAR(64),
    seller_zip_code_prefix VARCHAR(16),
    seller_city            VARCHAR(128),
    seller_state           VARCHAR(8)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS stg_category_translation;
CREATE TABLE stg_category_translation (
    product_category_name         VARCHAR(128),
    product_category_name_english VARCHAR(128)
) ENGINE=InnoDB;
