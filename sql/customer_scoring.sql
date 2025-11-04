WITH orders AS (
  SELECT
    customer_id,
    DATE(order_purchase_ts) AS purchase_date,
    order_id
  FROM `e-commerce-476011.olist_core.orders`
),
money AS (
  SELECT 
    order_id, 
    SUM(price) AS revenue
  FROM `e-commerce-476011.olist_core.order_items`
  GROUP BY 1
),
cust AS (
  SELECT
    o.customer_id,
    MAX(o.purchase_date) AS last_purchase,
    COUNT(DISTINCT o.order_id) AS freq_orders,
    SUM(m.revenue) AS monetary
  FROM orders o
  LEFT JOIN money m USING(order_id)
  GROUP BY o.customer_id
),
with_ref AS (
  SELECT
    *,
    (SELECT MAX(purchase_date) FROM orders) AS max_date,
    DATE_DIFF((SELECT MAX(purchase_date) FROM orders), last_purchase, DAY) AS recency_days
  FROM cust
),
ranks AS (
  SELECT
    *,
    -- lower recency_days is better → invert percentile later
    PERCENT_RANK() OVER (ORDER BY recency_days ASC)   AS pr_recency,   -- 0 best (most recent), 1 worst
    PERCENT_RANK() OVER (ORDER BY freq_orders  ASC)   AS pr_freq,      -- 0 low, 1 high
    PERCENT_RANK() OVER (ORDER BY monetary     ASC)   AS pr_monetary   -- 0 low, 1 high
  FROM with_ref
)
SELECT
  customer_id,
  recency_days,
  freq_orders,
  monetary,

  -- Convert to 0..100 scores where higher = better
  ( (1 - pr_recency) * 100 ) AS recency_score,
  ( pr_freq         * 100 )  AS frequency_score,
  ( pr_monetary     * 100 )  AS monetary_score,

  -- Weighted overall customer value score (tweak weights as you like)
  (
    (1 - pr_recency) * 0.4 +
     pr_freq         * 0.3 +
     pr_monetary     * 0.3
  ) * 100 AS customer_value_score,

  CASE
    WHEN (
      (1 - pr_recency) * 0.4 +
       pr_freq         * 0.3 +
       pr_monetary     * 0.3
    ) >= 0.80 THEN 'VIP'
    WHEN (
      (1 - pr_recency) * 0.4 +
       pr_freq         * 0.3 +
       pr_monetary     * 0.3
    ) >= 0.60 THEN 'Loyal'
    WHEN (
      (1 - pr_recency) * 0.4 +
       pr_freq         * 0.3 +
       pr_monetary     * 0.3
    ) >= 0.40 THEN 'Active'
    ELSE 'At Risk'
  END AS customer_segment
FROM ranks
ORDER BY customer_value_score DESC;
