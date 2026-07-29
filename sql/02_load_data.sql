-- =====================================================================
-- 02_load_data.sql
-- Bulk-loads the nine cleaned CSVs into the staging tables.
--
-- PREREQUISITE — local_infile must be enabled on BOTH sides:
--   Server:  SET GLOBAL local_infile = 1;
--   Client:  mysql --local-infile=1 -u root -p olist < sql/02_load_data.sql
--
-- MySQL Workbench users: Edit > Preferences > SQL Editor >
--   "Allow LOAD DATA LOCAL INFILE" must be checked, then reconnect.
--
-- Paths below are RELATIVE to where you launch the mysql client.
-- Use absolute paths if you get "File not found".
-- =====================================================================

USE olist;

SET @start := NOW();

-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE 'data/clean/olist_customers_dataset.csv'
INTO TABLE stg_customers
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(customer_id, customer_unique_id, customer_zip_code_prefix,
 customer_city, customer_state);

-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE 'data/clean/olist_geolocation_dataset.csv'
INTO TABLE stg_geolocation
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(geolocation_zip_code_prefix, geolocation_lat, geolocation_lng,
 geolocation_city, geolocation_state);

-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE 'data/clean/olist_orders_dataset.csv'
INTO TABLE stg_orders
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(order_id, customer_id, order_status, order_purchase_timestamp,
 order_approved_at, order_delivered_carrier_date,
 order_delivered_customer_date, order_estimated_delivery_date);

-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE 'data/clean/olist_order_items_dataset.csv'
INTO TABLE stg_order_items
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(order_id, order_item_id, product_id, seller_id,
 shipping_limit_date, price, freight_value);

-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE 'data/clean/olist_order_payments_dataset.csv'
INTO TABLE stg_order_payments
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(order_id, payment_sequential, payment_type,
 payment_installments, payment_value);

-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE 'data/clean/olist_order_reviews_dataset.csv'
INTO TABLE stg_order_reviews
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(review_id, order_id, review_score,
 review_creation_date, review_answer_timestamp);

-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE 'data/clean/olist_products_dataset.csv'
INTO TABLE stg_products
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(product_id, product_category_name, product_name_lenght,
 product_description_lenght, product_photos_qty, product_weight_g,
 product_length_cm, product_height_cm, product_width_cm);

-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE 'data/clean/olist_sellers_dataset.csv'
INTO TABLE stg_sellers
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(seller_id, seller_zip_code_prefix, seller_city, seller_state);

-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE 'data/clean/product_category_name_translation.csv'
INTO TABLE stg_category_translation
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(product_category_name, product_category_name_english);

-- ---------------------------------------------------------------------
-- Load receipt. Compare these against the counts printed by prep_csvs.py.
-- Expected (Olist v2, Nov 2018 snapshot):
--   customers 99,441 | geolocation 1,000,163 | orders 99,441
--   order_items 112,650 | payments 103,886 | reviews 99,224
--   products 32,951 | sellers 3,095 | category_translation 71
-- ---------------------------------------------------------------------
SELECT 'stg_customers'           AS table_name, COUNT(*) AS rows_loaded FROM stg_customers
UNION ALL SELECT 'stg_geolocation',          COUNT(*) FROM stg_geolocation
UNION ALL SELECT 'stg_orders',               COUNT(*) FROM stg_orders
UNION ALL SELECT 'stg_order_items',          COUNT(*) FROM stg_order_items
UNION ALL SELECT 'stg_order_payments',       COUNT(*) FROM stg_order_payments
UNION ALL SELECT 'stg_order_reviews',        COUNT(*) FROM stg_order_reviews
UNION ALL SELECT 'stg_products',             COUNT(*) FROM stg_products
UNION ALL SELECT 'stg_sellers',              COUNT(*) FROM stg_sellers
UNION ALL SELECT 'stg_category_translation', COUNT(*) FROM stg_category_translation;

SELECT CONCAT('Load finished in ', TIMESTAMPDIFF(SECOND, @start, NOW()), 's') AS elapsed;
