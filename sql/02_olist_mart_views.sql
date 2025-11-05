-- Main sales mart (one row per order-item)
CREATE OR REPLACE VIEW `e-commerce-476011.olist_mart.v_sales` AS
SELECT
  o.order_id, 
  o.customer_id, 
  o.purchase_date, 
  o.purchase_year, 
  o.purchase_month,
  i.order_item_id, 
  i.product_id, 
  pr.category_en, 
  i.seller_id,
  i.price, 
  i.freight_value, 
  (i.price + i.freight_value) AS gross_item_value,
  pay.payment_total, 
  pay.payment_types, 
  pay.max_installments,
  o.leadtime_days, 
  o.delivery_delay_days,
  r.review_score
  
FROM `e-commerce-476011.olist_core.v_orders_enriched` o
JOIN `e-commerce-476011.olist_core.order_items` i USING(order_id)
LEFT JOIN `e-commerce-476011.olist_core.products` pr ON pr.product_id = i.product_id
LEFT JOIN `e-commerce-476011.olist_core.v_payments_by_order` pay USING(order_id)
LEFT JOIN `e-commerce-476011.olist_core.v_reviews_latest` r USING(order_id);

-- Distance (seller zip → customer zip)
CREATE OR REPLACE VIEW `e-commerce-476011.olist_mart.v_sales_with_distance` AS
WITH zc AS (
  SELECT c.customer_id, gz.geog AS cust_geog
  FROM `e-commerce-476011.olist_core.customers` c
  LEFT JOIN `e-commerce-476011.olist_core.geo_zip` gz ON gz.zip_prefix = c.zip_prefix
),
zs AS (
  SELECT s.seller_id, gz.geog AS sell_geog
  FROM `e-commerce-476011.olist_core.sellers` s
  LEFT JOIN `e-commerce-476011.olist_core.geo_zip` gz ON gz.zip_prefix = s.zip_prefix
)
SELECT
  s.*,
  SAFE_DIVIDE(ST_DISTANCE(zc.cust_geog, zs.sell_geog), 1000.0) AS distance_km
FROM `e-commerce-476011.olist_mart.v_sales` s
LEFT JOIN zc ON zc.customer_id = s.customer_id
LEFT JOIN zs ON zs.seller_id   = s.seller_id;
