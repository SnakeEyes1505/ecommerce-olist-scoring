# E-Commerce (Olist) Scoring Project

This project uses the **Brazilian E-Commerce Public Dataset by Olist** and **Google BigQuery** to build scoring systems for:

- **Sellers** – quality and risk
- **Products** – popularity and quality
- **Customers** – value and engagement (RFM)

## Data

Original data: Olist Brazilian e-commerce dataset  
(Tables: orders, order_items, customers, sellers, products, reviews, payments, geolocation.)

I worked in **BigQuery Sandbox**, built core views, and then created three mart tables:

- `seller_scores`
- `product_scores`
- `customer_scores`

## Scoring logic

### Seller score

-- Seller scoring pipeline
-- Input: Olist core tables in BigQuery (orders, order_items, reviews, payments, sellers, products)
-- Output: olist_mart.seller_scores
-- Dimensions:
--   1) Delivery reliability    (late_rate, avg_delay_days, overall_review)
--   2) Product quality         (bad_review_rate, product_avg_review)
--   3) Pricing fairness        (price_index vs market median)
--   4) Shipping fairness       (freight_per_km, shipping_review)
-- Each dimension is normalized to 0–100 using percentile ranks and combined into an overall score and tier.

Dimensions:

1. **Delivery reliability**
   - Late delivery rate
   - Average delivery delay days
   - Overall review score

2. **Product quality**
   - Bad review rate (1–2 stars)
   - Average review score on that seller’s orders

3. **Pricing fairness**
   - Seller’s average price vs market median price for the same product (price index)

4. **Shipping fairness**
   - Freight per km vs distance
   - Review score after shipping

Each dimension is normalized (0–100) and combined into an overall seller score and a tier:

- `TOP SELLER`
- `OK / WATCH`
- `RISKY`

SQL: see [`sql/seller_scoring.sql`](sql/seller_scoring.sql)

### Product score

Dimensions:

- Popularity (units sold)
- Satisfaction (bad review rate + avg review)
- Delivery experience (delay and late rate for that product)
- Price position within category (median price vs category median)
- Shipping burden (freight per km)

SQL: [`sql/product_scoring.sql`](sql/product_scoring.sql)

### Customer score

RFM-style scoring per customer:

- **Recency** – days since last purchase
- **Frequency** – number of orders
- **Monetary** – total spending

Combined into a `customer_value_score` and segments like:

- `VIP`
- `Loyal`
- `Active`
- `At Risk`

SQL: [`sql/customer_scoring.sql`](sql/customer_scoring.sql)

## How to run

1. Load the Olist tables into BigQuery.
2. Create any helper views (distance, enriched orders).
3. Run the SQL scripts in `sql/` to create the score tables.
4. Use the score tables in dashboards or exports (e.g. to Kaggle/Tableau).

---

This repo is part of my learning portfolio in SQL and analytics.
