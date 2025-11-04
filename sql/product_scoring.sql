WITH base AS (
  SELECT
    s.order_id,
    s.product_id,
    s.seller_id,
    s.customer_id,
    s.category_en,
    CAST(s.price AS NUMERIC)           AS price,
    CAST(s.freight_value AS NUMERIC)   AS freight_value,
    s.distance_km,
    s.review_score,
    s.delivery_delay_days,
    (p.product_length_cm * p.product_width_cm * p.product_height_cm) AS vol_cm3
  FROM `e-commerce-476011.olist_mart.v_sales_with_distance` s
  LEFT JOIN `e-commerce-476011.olist_core.products` p
    ON p.product_id = s.product_id
),

-- -------- Product-level KPIs --------
product_kpis AS (
  SELECT
    b.product_id,
    ANY_VALUE(category_en)                       AS category_en,
    COUNT(*)                                     AS units_sold,
    COUNT(DISTINCT order_id)                     AS orders,
    COUNT(DISTINCT b.customer_id)                  AS customers,
    -- repeat customers for this product
    SAFE_DIVIDE(
      COUNTIF(rep.cust_orders_prod >= 2), 
      COUNT(DISTINCT b.customer_id)
    )                                            AS repeat_customer_rate,
    -- pricing
    APPROX_QUANTILES(price, 2)[OFFSET(1)]        AS median_price,
    AVG(price)                                   AS avg_price,
    STDDEV(price)                                AS price_volatility,
    -- satisfaction
    AVG(review_score)                            AS avg_review,
    AVG(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END) AS bad_review_rate,
    -- delivery experience
    AVG(delivery_delay_days)                     AS avg_delay_days,
    AVG(CASE WHEN delivery_delay_days > 0 THEN 1 ELSE 0 END) AS late_rate,
    -- shipping price
    AVG(SAFE_DIVIDE(freight_value, NULLIF(distance_km,0))) AS avg_freight_per_km,
    -- size proxy
    AVG(vol_cm3)                                 AS avg_vol_cm3
  FROM base b
  LEFT JOIN (
    SELECT product_id, customer_id, COUNT(DISTINCT order_id) AS cust_orders_prod
    FROM base
    GROUP BY product_id, customer_id
  ) rep
  ON rep.product_id = b.product_id AND rep.customer_id = b.customer_id
  GROUP BY product_id
),

-- Category reference medians (to compare product price position inside its category)
category_refs AS (
  SELECT
    category_en,
    APPROX_QUANTILES(median_price, 2)[OFFSET(1)] AS cat_median_of_medians
  FROM product_kpis
  GROUP BY category_en
),

-- Attach category price reference and compute price_position (<=1 good / cheaper than cat median)
with_refs AS (
  SELECT
    pk.*,
    cr.cat_median_of_medians,
    SAFE_DIVIDE(pk.median_price, cr.cat_median_of_medians) AS price_position
  FROM product_kpis pk
  LEFT JOIN category_refs cr USING(category_en)
),

-- Optional: filter to products with enough evidence
filtered AS (
  SELECT *
  FROM with_refs
  WHERE units_sold >= 20   -- tweak threshold if your dataset is small
),

-- -------- Percentile ranks (0..1) to normalize KPIs --------
ranks AS (
  SELECT
    f.*,

    -- HIGHER is better
    IFNULL(PERCENT_RANK() OVER (ORDER BY f.units_sold           ASC), 0.5) AS pr_units,          -- popularity
    IFNULL(PERCENT_RANK() OVER (ORDER BY f.avg_review           ASC), 0.5) AS pr_avg_review,

    -- LOWER is better (we invert later with 1 - pr)
    IFNULL(PERCENT_RANK() OVER (ORDER BY f.bad_review_rate      ASC), 0.5) AS pr_bad_rate,
    IFNULL(PERCENT_RANK() OVER (ORDER BY f.avg_delay_days       ASC), 0.5) AS pr_delay,
    IFNULL(PERCENT_RANK() OVER (ORDER BY f.late_rate            ASC), 0.5) AS pr_late_rate,
    IFNULL(PERCENT_RANK() OVER (ORDER BY f.price_position       ASC), 0.5) AS pr_price_pos,      -- cheaper vs category
    IFNULL(PERCENT_RANK() OVER (ORDER BY f.avg_freight_per_km   ASC), 0.5) AS pr_freight_km
  FROM filtered f
),

-- -------- Sub-scores (0..100, higher = better) --------
subscores AS (
  SELECT
    r.*,

    -- Popularity: units sold (by itself; you can mix in revenue if you want)
    ( r.pr_units * 100 ) AS popularity_score,

    -- Satisfaction: low bad_review_rate (60%) + high avg_review (40%)
    ( (1 - r.pr_bad_rate) * 0.60 + r.pr_avg_review * 0.40 ) * 100 AS satisfaction_score,

    -- Delivery experience: low delay (60%) + low late_rate (40%)
    ( (1 - r.pr_delay) * 0.60 + (1 - r.pr_late_rate) * 0.40 ) * 100 AS delivery_score,

    -- Price position within category: lower is better
    ( (1 - r.pr_price_pos) * 100 ) AS price_position_score,

    -- Shipping burden: lower freight per km is better
    ( (1 - r.pr_freight_km) * 100 ) AS shipping_score
  FROM ranks r
),

-- -------- Overall product score (tweak weights to taste) --------
scored AS (
  SELECT
    s.*,
    (
      s.popularity_score   * 0.15  +   -- demand
      s.satisfaction_score * 0.35  +   -- what buyers feel
      s.delivery_score     * 0.20  +   -- reliability experience for this product
      s.price_position_score * 0.20 +   -- relative price inside category
      s.shipping_score     * 0.10      -- logistics burden for buyers
    ) AS overall_product_score
  FROM subscores s
)

SELECT
  product_id,
  category_en,
  units_sold,
  customers,
  repeat_customer_rate,
  median_price,
  avg_price,
  price_volatility,
  avg_review,
  bad_review_rate,
  avg_delay_days,
  late_rate,
  avg_freight_per_km,
  avg_vol_cm3,

  -- Sub-scores
  ROUND(popularity_score,2)     AS popularity_score,
  ROUND(satisfaction_score,2)   AS satisfaction_score,
  ROUND(delivery_score,2)       AS delivery_score,
  ROUND(price_position_score,2) AS price_position_score,
  ROUND(shipping_score,2)       AS shipping_score,

  -- Final
  ROUND(overall_product_score,2) AS overall_product_score,
  CASE
    WHEN overall_product_score >= 80 THEN 'HERO'
    WHEN overall_product_score >= 60 THEN 'STRONG'
    WHEN overall_product_score >= 40 THEN 'NICHE'
    ELSE 'RISKY'
  END AS product_tier
FROM scored
ORDER BY overall_product_score DESC;
