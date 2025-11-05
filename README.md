# E-Commerce (Olist) Scoring Project

## Project overview

Goal: use the Brazilian Olist e-commerce dataset to build **three scoring systems**:

- **Seller score** – identify risky vs top sellers using delivery reliability, complaints, price fairness, and shipping fairness.
- **Product score** – rank products by popularity, quality, delivery experience, price position in category, and shipping burden.
- **Customer score (RFM)** – segment customers into VIP / Loyal / Active / At Risk based on recency, frequency, and monetary value.

All transformations are done in **BigQuery (SQL)**, and the final scores can be used for dashboards, monitoring, or recommendation rules.

## Project phases

I followed a simple 4-phase workflow for this project:

1. **Ask** – define the questions
2. **Prepare** – clean and standardize the raw Olist data
3. **Process** – build reusable feature views / marts
4. **Analyze** – calculate scores and produce insights

### 1. Ask

Key business questions:

- Which **sellers** are good vs risky, considering delivery, complaints, prices, and shipping?
- Which **products** are “heroes” vs problematic?
- Which **customers** are most valuable (VIP / Loyal) and which are at risk of churning?
- How do distance, freight value, and delivery performance affect reviews?

These questions drove how I designed the data model and scores.

### 2. Prepare (olist_core)

Goal: turn the raw Olist CSV tables into a consistent **core layer** in BigQuery.

Main steps (see [`sql/olist_core.sql`](sql/olist_core.sql)):

(see [`sql/01_olist_core_views.sql`](sql/01_olist_core_views.sql)):

- `v_orders_enriched`  
  - adds `purchase_date`, `delivered_date`, `estimated_date`  
  - computes `delivery_delay_days` (positive = late, negative = early)
- `v_reviews_latest`  
  - keeps one latest review per `order_id`
- `v_payments_by_order`  
  - aggregates multiple payment rows per order

This core layer is used by all later calculations.

### 3. Process (olist_mart)

Goal: build **denormalized views** and feature tables used directly for analytics and scoring.

Main steps (see [`sql/02_olist_mart_views.sql`](sql/02_olist_mart_views.sql)):

- `v_sales`  
  - order-item level fact table combining orders, items, customers, sellers, products, and reviews
- `v_sales_with_distance`  
  - extends `v_sales` with customer–seller distance (km) using geolocation

## Data

Original data: Olist Brazilian e-commerce dataset  
(Tables: orders, order_items, customers, sellers, products, reviews, payments, geolocation.)

I worked in **BigQuery Sandbox**, built core views, and then created three mart tables:

- `seller_scores`
- `product_scores`
- `customer_scores`

## Scoring logic

### Seller score

**Seller scoring pipeline**
 
Input: Olist core tables in BigQuery (orders, order_items, reviews, payments, sellers, products)
Output: olist_mart.seller_scores
 
**Dimensions:**

 1. Delivery reliability    (late_rate, avg_delay_days, overall_review)
 2. Product quality         (bad_review_rate, product_avg_review)
 3. Pricing fairness        (price_index vs market median)
 4. Shipping fairness       (freight_per_km, shipping_review)
    
 Each dimension is normalized to 0–100 using percentile ranks and combined into an overall score and tier.

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

### Seller score distribution
![Seller score distribution](images/Picture1Seller score.png)
![Seller score distribution](images/Picture2Seller score.png)

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
