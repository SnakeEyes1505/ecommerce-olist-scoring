-- ORDERS (your raw is olist_order)
CREATE OR REPLACE TABLE `e-commerce-476011.olist_core.orders` AS
SELECT
  order_id,
  customer_id,
  order_status,
  order_purchase_timestamp      AS order_purchase_ts,
  order_approved_at             AS order_approved_ts,
  order_delivered_carrier_date  AS delivered_carrier_ts,
  order_delivered_customer_date AS delivered_customer_ts,
  order_estimated_delivery_date AS estimated_delivery_ts
FROM `e-commerce-476011.e_commerce.olist_order`;

-- ORDER ITEMS
CREATE OR REPLACE TABLE `e-commerce-476011.olist_core.order_items` AS
SELECT
  order_id, order_item_id, product_id, seller_id,
  SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', shipping_limit_date) AS shipping_limit_ts,
  CAST(price AS NUMERIC)         AS price,
  CAST(freight_value AS NUMERIC) AS freight_value
FROM `e-commerce-476011.e_commerce.olist_order_items`;

-- PAYMENTS
CREATE OR REPLACE TABLE `e-commerce-476011.olist_core.payments` AS
SELECT
  order_id,
  CAST(payment_sequential AS INT64)   AS payment_seq,
  payment_type,
  CAST(payment_installments AS INT64) AS payment_installments,
  CAST(payment_value AS NUMERIC)      AS payment_value
FROM `e-commerce-476011.e_commerce.olist_order_payments`;

-- REVIEWS
CREATE OR REPLACE TABLE `e-commerce-476011.olist_core.reviews` AS
SELECT
  review_id, order_id,
  CAST(review_score AS INT64) AS review_score,
  SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', review_creation_date)    AS review_created_ts,
  SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', review_answer_timestamp) AS review_answered_ts
FROM `e-commerce-476011.e_commerce.olist_order_reviews`;

-- PRODUCTS (with English category)
CREATE OR REPLACE TABLE `e-commerce-476011.olist_core.products` AS
SELECT
  p.product_id,
  COALESCE(t.product_category_name_english, p.product_category_name) AS category_en,
  CAST(product_weight_g  AS NUMERIC) AS product_weight_g,
  CAST(product_length_cm AS NUMERIC) AS product_length_cm,
  CAST(product_height_cm AS NUMERIC) AS product_height_cm,
  CAST(product_width_cm  AS NUMERIC) AS product_width_cm
FROM `e-commerce-476011.e_commerce.olist_products` p
LEFT JOIN `e-commerce-476011.e_commerce.product_category_name_translation` t
  ON t.product_category_name = p.product_category_name;

-- CUSTOMERS
CREATE OR REPLACE TABLE `e-commerce-476011.olist_core.customers` AS
SELECT
  customer_id, customer_unique_id,
  CAST(customer_zip_code_prefix AS INT64) AS zip_prefix,
  customer_city, customer_state
FROM `e-commerce-476011.e_commerce.olist_customers`;

-- SELLERS
CREATE OR REPLACE TABLE `e-commerce-476011.olist_core.sellers` AS
SELECT
  seller_id,
  CAST(seller_zip_code_prefix AS INT64) AS zip_prefix,
  seller_city, seller_state
FROM `e-commerce-476011.e_commerce.olist_sellers`;

-- GEO: centroid per zip_prefix + GEOGRAPHY for distances
CREATE OR REPLACE TABLE `e-commerce-476011.olist_core.geo_zip` AS
SELECT
  CAST(geolocation_zip_code_prefix AS INT64) AS zip_prefix,
  AVG(geolocation_lat)  AS lat,
  AVG(geolocation_lng)  AS lng,
  ST_GEOGPOINT(AVG(geolocation_lng), AVG(geolocation_lat)) AS geog
FROM `e-commerce-476011.e_commerce.olist_geolocation`
GROUP BY 1;
