-- ONE review per order (latest answered)
CREATE OR REPLACE VIEW `e-commerce-476011.olist_core.v_reviews_latest` AS
SELECT order_id, review_score
FROM (
  SELECT order_id, review_score,
         ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY review_answered_ts DESC) AS rn
  FROM `e-commerce-476011.olist_core.reviews`
) WHERE rn = 1;

-- Orders enriched with leadtime & delay
CREATE OR REPLACE VIEW `e-commerce-476011.olist_core.v_orders_enriched` AS
SELECT
  o.*,
  DATE(o.order_purchase_ts) AS purchase_date,
  EXTRACT(YEAR FROM o.order_purchase_ts)  AS purchase_year,
  EXTRACT(MONTH FROM o.order_purchase_ts) AS purchase_month,
  SAFE.DATE_DIFF(DATE(o.delivered_customer_ts), DATE(o.order_purchase_ts), DAY) AS leadtime_days,
  SAFE.DATE_DIFF(DATE(o.delivered_customer_ts), DATE(o.estimated_delivery_ts), DAY) AS delivery_delay_days
FROM `e-commerce-476011.olist_core.orders` o;

-- Payments aggregated to order
CREATE OR REPLACE VIEW `e-commerce-476011.olist_core.v_payments_by_order` AS
SELECT
  order_id,
  SUM(payment_value) AS payment_total,
  STRING_AGG(DISTINCT payment_type ORDER BY payment_type) AS payment_types,
  MAX(payment_installments) AS max_installments
FROM `e-commerce-476011.olist_core.payments`
GROUP BY 1;
