-- 1. RELIABILITY / DELIVERY

WITH per_order_seller AS (
  SELECT
    oi.seller_id,
    oi.order_id,
    ANY_VALUE(o.delivery_delay_days) AS delivery_delay_days,
    ANY_VALUE(r.review_score)        AS review_score
  FROM `e-commerce-476011.olist_core.order_items` oi
  JOIN `e-commerce-476011.olist_core.v_orders_enriched` o USING(order_id)
  LEFT JOIN `e-commerce-476011.olist_core.v_reviews_latest` r USING(order_id)
  GROUP BY oi.seller_id, oi.order_id
),
seller_reliability AS (
  SELECT
    seller_id,
    COUNT(*) AS orders_served,
    AVG(CASE WHEN delivery_delay_days > 0 THEN 1 ELSE 0 END) AS late_rate,
    AVG(delivery_delay_days) AS avg_delay_days,
    AVG(review_score)        AS seller_overall_review
  FROM per_order_seller
  GROUP BY seller_id
),

-- 2. PRODUCT QUALITY
item_level AS (
  SELECT
    oi.seller_id,
    oi.product_id,
    r.review_score
  FROM `e-commerce-476011.olist_core.order_items` oi
  LEFT JOIN `e-commerce-476011.olist_core.v_reviews_latest` r USING(order_id)
),
seller_product_quality AS (
  SELECT
    seller_id,
    COUNT(*) AS units_sold,
    AVG(review_score) AS prod_avg_review,
    AVG(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END) AS bad_review_rate
  FROM item_level
  GROUP BY seller_id
),

-- 3. PRICE FAIRNESS
seller_product_price AS (
  SELECT
    seller_id,
    product_id,
    AVG(price) AS seller_avg_price,
    COUNT(*)  AS units_sold_product
  FROM `e-commerce-476011.olist_core.order_items`
  GROUP BY seller_id, product_id
),
market_product_price AS (
  SELECT
    product_id,
    APPROX_QUANTILES(price, 2)[OFFSET(1)] AS market_median_price
  FROM `e-commerce-476011.olist_core.order_items`
  GROUP BY product_id
),
seller_price_fairness AS (
  SELECT
    spp.seller_id,
    AVG(SAFE_DIVIDE(spp.seller_avg_price, mpp.market_median_price)) AS avg_price_index
  FROM seller_product_price spp
  JOIN market_product_price mpp USING(product_id)
  GROUP BY spp.seller_id
),

-- 4. SHIPPING FAIRNESS
ship_level AS (
  SELECT
    s.seller_id,
    s.freight_value,
    s.distance_km,
    r.review_score
  FROM `e-commerce-476011.olist_mart.v_sales_with_distance` s
  LEFT JOIN `e-commerce-476011.olist_core.v_reviews_latest` r USING(order_id)
  WHERE s.distance_km IS NOT NULL
),
seller_shipping_fairness AS (
  SELECT
    seller_id,
    COUNT(*) AS shipments,
    AVG(SAFE_DIVIDE(freight_value, distance_km)) AS avg_freight_per_km,
    AVG(review_score) AS ship_avg_review
  FROM ship_level
  GROUP BY seller_id
),

-- 5. JOIN EVERYTHING PER SELLER
all_metrics AS (
  SELECT
    r.seller_id,
    r.orders_served,
    r.late_rate,
    r.avg_delay_days,
    r.seller_overall_review,
    q.units_sold,
    q.prod_avg_review,
    q.bad_review_rate,
    p.avg_price_index,
    sh.shipments,
    sh.avg_freight_per_km,
    sh.ship_avg_review
  FROM seller_reliability r
  LEFT JOIN seller_product_quality    q  USING(seller_id)
  LEFT JOIN seller_price_fairness     p  USING(seller_id)
  LEFT JOIN seller_shipping_fairness  sh USING(seller_id)
  WHERE r.orders_served >= 20          -- ignore sellers with too little data
),

-- Normalize each KPI to 0..100 via percentile ranks, then compute sub-scores
scored AS (
  SELECT
    am.*,

    -- Percentile ranks (0..1). Use IFNULL to treat NULLs neutrally (0.5).
    -- LOWER is better → invert later with (1 - pr)
    IFNULL(PERCENT_RANK() OVER (ORDER BY am.late_rate                ASC), 0.5) AS pr_late_rate,
    IFNULL(PERCENT_RANK() OVER (ORDER BY am.bad_review_rate          ASC), 0.5) AS pr_bad_rate,
    IFNULL(PERCENT_RANK() OVER (ORDER BY am.avg_price_index          ASC), 0.5) AS pr_price_index,
    IFNULL(PERCENT_RANK() OVER (ORDER BY am.avg_freight_per_km       ASC), 0.5) AS pr_freight_km,

    -- HIGHER is better → keep as-is
    IFNULL(PERCENT_RANK() OVER (ORDER BY am.seller_overall_review    ASC), 0.5) AS pr_overall_review,
    IFNULL(PERCENT_RANK() OVER (ORDER BY am.prod_avg_review          ASC), 0.5) AS pr_prod_review,
    IFNULL(PERCENT_RANK() OVER (ORDER BY am.ship_avg_review          ASC), 0.5) AS pr_ship_review

  FROM all_metrics am
),

final_scores AS (
  SELECT
    s.*,

    -- 1) Reliability: low late_rate (invert) + high overall review
    ( (1 - s.pr_late_rate) * 0.60 + s.pr_overall_review * 0.40 ) * 100
      AS reliability_score,

    -- 2) Product quality: low bad_review_rate (invert) + high product review
    ( (1 - s.pr_bad_rate) * 0.60 + s.pr_prod_review * 0.40 ) * 100
      AS product_quality_score,

    -- 3) Pricing fairness: low price index is better
    ( (1 - s.pr_price_index) * 100 ) AS pricing_fairness_score,

    -- 4) Shipping fairness: low freight/km (invert) + high ship review
    ( (1 - s.pr_freight_km) * 0.70 + s.pr_ship_review * 0.30 ) * 100
      AS shipping_fairness_score
  FROM scored s
)

SELECT
  seller_id,
  orders_served,
  shipments,
  reliability_score,
  product_quality_score,
  pricing_fairness_score,
  shipping_fairness_score,
  (
    reliability_score       * 0.35 +
    product_quality_score   * 0.30 +
    pricing_fairness_score  * 0.20 +
    shipping_fairness_score * 0.15
  ) AS overall_seller_score,
  CASE
    WHEN (
      reliability_score       * 0.35 +
      product_quality_score   * 0.30 +
      pricing_fairness_score  * 0.20 +
      shipping_fairness_score * 0.15
    ) >= 80 THEN 'TOP SELLER'
    WHEN (
      reliability_score       * 0.35 +
      product_quality_score   * 0.30 +
      pricing_fairness_score  * 0.20 +
      shipping_fairness_score * 0.15
    ) >= 40 THEN 'OK / WATCH'
    ELSE 'RISKY'
  END AS seller_tier
FROM final_scores
ORDER BY overall_seller_score DESC;
