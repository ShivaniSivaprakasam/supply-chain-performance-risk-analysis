-- ============================================================
-- Step 1: Data Quality Verification
-- Purpose: Confirm the load preserved data correctly, and resolve
--          the open questions flagged in Step 1 (Type values,
--          duplicate-looking ID pairs, Order Zipcode nulls)
-- ============================================================

USE supply_chain_analysis;

-- ------------------------------------------------------------
-- 1. Confirm dates loaded correctly (not NULL, sensible range)
-- ------------------------------------------------------------
SELECT
    MIN(order_date) AS earliest_order,
    MAX(order_date) AS latest_order,
    SUM(CASE WHEN order_date IS NULL THEN 1 ELSE 0 END) AS null_order_dates,
    SUM(CASE WHEN shipping_date IS NULL THEN 1 ELSE 0 END) AS null_shipping_dates
FROM orders_raw;

-- ------------------------------------------------------------
-- 2. Resolve the "Type" column ambiguity flagged in Step 1
--    (checking actual distinct values instead of assuming)
-- ------------------------------------------------------------
SELECT type, COUNT(*) AS row_count
FROM orders_raw
GROUP BY type
ORDER BY row_count DESC;

-- ------------------------------------------------------------
-- 3. Check whether customer_id and order_customer_id are truly
--    duplicates of each other, or serve different purposes
-- ------------------------------------------------------------
SELECT COUNT(*) AS mismatched_rows
FROM orders_raw
WHERE customer_id <> order_customer_id;

-- ------------------------------------------------------------
-- 4. Check whether product_card_id and order_item_cardprod_id
--    are duplicates of each other
-- ------------------------------------------------------------
SELECT COUNT(*) AS mismatched_rows
FROM orders_raw
WHERE product_card_id <> order_item_cardprod_id;

-- ------------------------------------------------------------
-- 5. Check whether category_id and product_category_id
--    are duplicates of each other
-- ------------------------------------------------------------
SELECT COUNT(*) AS mismatched_rows
FROM orders_raw
WHERE category_id <> product_category_id;

-- ------------------------------------------------------------
-- 6. Check the Order Zipcode null rate flagged in Step 1
-- ------------------------------------------------------------
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN order_zipcode IS NULL OR order_zipcode = '' THEN 1 ELSE 0 END) AS null_order_zipcode,
    ROUND(SUM(CASE WHEN order_zipcode IS NULL OR order_zipcode = '' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS null_pct
FROM orders_raw;

-- ------------------------------------------------------------
-- 7. General null-check across other key business columns
-- ------------------------------------------------------------
SELECT
    SUM(CASE WHEN benefit_per_order IS NULL THEN 1 ELSE 0 END) AS null_benefit,
    SUM(CASE WHEN sales IS NULL THEN 1 ELSE 0 END) AS null_sales,
    SUM(CASE WHEN order_item_profit_ratio IS NULL THEN 1 ELSE 0 END) AS null_profit_ratio,
    SUM(CASE WHEN delivery_status IS NULL THEN 1 ELSE 0 END) AS null_delivery_status
FROM orders_raw;

-- ------------------------------------------------------------
-- 8. Duplicate row check (same order_item_id appearing more than once
--    would indicate the load duplicated data or the source has dupes)
-- ------------------------------------------------------------
SELECT order_item_id, COUNT(*) AS occurrence_count
FROM orders_raw
GROUP BY order_item_id
HAVING COUNT(*) > 1;

-- ------------------------------------------------------------
-- 9. Sanity check on access_logs_raw
-- ------------------------------------------------------------
SELECT
    MIN(log_date) AS earliest_log,
    MAX(log_date) AS latest_log,
    COUNT(DISTINCT product) AS distinct_products,
    COUNT(DISTINCT category) AS distinct_categories,
    SUM(CASE WHEN log_date IS NULL THEN 1 ELSE 0 END) AS null_log_dates
FROM access_logs_raw;

-- ============================================================
-- Step 2: Create orders_clean
-- Purpose: Analysis-ready version of orders_raw with:
--          - Redundant duplicate ID columns removed
--          - order_zipcode excluded (86.24% null, unusable)
--          - Column set finalized based on Step 2 data quality checks
-- ============================================================

USE supply_chain_analysis;

DROP TABLE IF EXISTS orders_clean;

CREATE TABLE orders_clean AS
SELECT
    order_item_id,              -- unique row-level identifier (grain of this table)
    order_id,                   -- groups line items into a single order
    type,                       -- payment method: DEBIT, TRANSFER, PAYMENT, CASH
    order_date,
    shipping_date,
    days_for_shipping_real,
    days_for_shipment_scheduled,
    delivery_status,
    late_delivery_risk,
    shipping_mode,
    customer_id,                -- canonical customer identifier (order_customer_id dropped, confirmed duplicate)
    customer_segment,
    customer_city,
    customer_state,
    customer_country,
    market,
    order_city,
    order_state,
    order_country,
    order_region,
    latitude,
    longitude,
    category_id,                -- canonical category identifier (product_category_id dropped, confirmed duplicate)
    category_name,
    department_id,
    department_name,
    product_card_id,            -- canonical product identifier (order_item_cardprod_id dropped, confirmed duplicate)
    product_name,
    product_price,
    product_status,
    order_status,
    order_item_quantity,
    order_item_discount,
    order_item_discount_rate,
    order_item_product_price,
    sales,
    order_item_total,
    sales_per_customer,
    benefit_per_order,
    order_profit_per_order,
    order_item_profit_ratio
FROM orders_raw;

-- ------------------------------------------------------------
-- Verify row count matches orders_raw (should be identical --
-- this step only removes columns, not rows)
-- ------------------------------------------------------------
SELECT
    (SELECT COUNT(*) FROM orders_raw)   AS raw_row_count,
    (SELECT COUNT(*) FROM orders_clean) AS clean_row_count;
    
-- ============================================================
-- Step 3B: Deeper Data Cleaning Checks
-- Purpose: Close remaining gaps before continuing analysis --
--          PII handling, numeric sanity, text consistency,
--          time-of-day validity, and cross-table name matching
-- ============================================================

USE supply_chain_analysis;

-- ------------------------------------------------------------
-- 1. Numeric sanity checks -- look for impossible values that
--    would silently distort profitability/sales analysis
-- ------------------------------------------------------------
SELECT
    SUM(CASE WHEN sales < 0 THEN 1 ELSE 0 END)                    AS negative_sales,
    SUM(CASE WHEN order_item_quantity <= 0 THEN 1 ELSE 0 END)     AS zero_or_negative_qty,
    SUM(CASE WHEN product_price <= 0 THEN 1 ELSE 0 END)           AS zero_or_negative_price,
    SUM(CASE WHEN order_item_discount_rate > 1 THEN 1 ELSE 0 END) AS discount_rate_over_100pct,
    SUM(CASE WHEN days_for_shipping_real < 0 THEN 1 ELSE 0 END)   AS negative_shipping_days,
    SUM(CASE WHEN days_for_shipment_scheduled < 0 THEN 1 ELSE 0 END) AS negative_scheduled_days
FROM orders_clean;

-- ------------------------------------------------------------
-- 2. Text/categorical consistency check -- look for casing or
--    naming inconsistencies that would fragment Tableau groupings
--    (checking a few high-impact columns, not every text column)
-- ------------------------------------------------------------
SELECT DISTINCT order_country
FROM orders_clean
ORDER BY order_country;

SELECT DISTINCT customer_segment
FROM orders_clean
ORDER BY customer_segment;

SELECT DISTINCT order_status
FROM orders_clean
ORDER BY order_status;

-- ------------------------------------------------------------
-- 3. Time-of-day sanity check -- confirm shipping/order timestamps
--    have real time variation, not just placeholder 00:00:00
-- ------------------------------------------------------------
SELECT
    SUM(CASE WHEN TIME(order_date) = '00:00:00' THEN 1 ELSE 0 END)    AS order_time_midnight_count,
    SUM(CASE WHEN TIME(shipping_date) = '00:00:00' THEN 1 ELSE 0 END) AS shipping_time_midnight_count,
    COUNT(*) AS total_rows
FROM orders_clean;

-- ------------------------------------------------------------
-- 4. Cross-table name matching -- check how many product/category
--    names in access_logs_raw actually match orders_clean, since
--    our planned aggregated join (Q17-18) depends on this
-- ------------------------------------------------------------
-- ------------------------------------------------------------
-- Get distinct product/category names from each table separately
-- (no join, no subquery -- just two lightweight independent selects)
-- ------------------------------------------------------------
SELECT DISTINCT product FROM access_logs_raw ORDER BY product;

SELECT DISTINCT category FROM access_logs_raw ORDER BY category;

SELECT DISTINCT product_name FROM orders_clean ORDER BY product_name;

SELECT DISTINCT category_name FROM orders_clean ORDER BY category_name;

-- ============================================================
-- Identify exactly which product/category names in access_logs_raw
-- fail to match orders_clean even after trimming whitespace
-- Purpose: Isolate the true mismatches (likely spelling/casing
--          differences) vs. ones that were just spacing issues
-- ============================================================

USE supply_chain_analysis;

-- Products still unmatched after trimming both sides
SELECT DISTINCT TRIM(a.product) AS access_product
FROM access_logs_raw a
WHERE TRIM(a.product) NOT IN (
    SELECT DISTINCT TRIM(product_name) FROM orders_clean
);

-- Categories still unmatched after trimming both sides
SELECT DISTINCT TRIM(a.category) AS access_category
FROM access_logs_raw a
WHERE TRIM(a.category) NOT IN (
    SELECT DISTINCT TRIM(category_name) FROM orders_clean
);

-- ============================================================
-- Step 4A (Rerun): Delivery Performance & Logistics
-- Source table: orders_clean
-- ============================================================

USE supply_chain_analysis;

-- ------------------------------------------------------------
-- Q1: What % of orders are delivered late, and does late
--     delivery risk vary by shipping mode?
-- ------------------------------------------------------------
SELECT
    shipping_mode,
    COUNT(*)                                            AS total_orders,
    SUM(late_delivery_risk)                              AS late_orders,
    ROUND(SUM(late_delivery_risk) * 100.0 / COUNT(*), 2) AS late_delivery_pct
FROM orders_clean
GROUP BY shipping_mode
ORDER BY late_delivery_pct DESC;


-- ------------------------------------------------------------
-- Q2: Which Order Regions/Markets have the worst late-delivery
--     rates -- is this a carrier problem or a geography problem?
-- ------------------------------------------------------------

-- By Market (broad view)
SELECT
    market,
    COUNT(*)                                            AS total_orders,
    SUM(late_delivery_risk)                              AS late_orders,
    ROUND(SUM(late_delivery_risk) * 100.0 / COUNT(*), 2) AS late_delivery_pct
FROM orders_clean
GROUP BY market
ORDER BY late_delivery_pct DESC;

-- By Order Region (granular view, within each market)
SELECT
    market,
    order_region,
    COUNT(*)                                            AS total_orders,
    SUM(late_delivery_risk)                              AS late_orders,
    ROUND(SUM(late_delivery_risk) * 100.0 / COUNT(*), 2) AS late_delivery_pct
FROM orders_clean
GROUP BY market, order_region
HAVING COUNT(*) >= 100   -- excludes regions with too few orders to be statistically meaningful
ORDER BY late_delivery_pct DESC;


-- ------------------------------------------------------------
-- Q3: Is there a shipping mode that consistently over-promises
--     (scheduled days) vs under-delivers (actual days)?
-- ------------------------------------------------------------
SELECT
    shipping_mode,
    ROUND(AVG(days_for_shipment_scheduled), 2) AS avg_scheduled_days,
    ROUND(AVG(days_for_shipping_real), 2)      AS avg_actual_days,
    ROUND(AVG(days_for_shipping_real - days_for_shipment_scheduled), 2) AS avg_gap_days,
    ROUND(STDDEV(days_for_shipping_real - days_for_shipment_scheduled), 2) AS gap_stddev
FROM orders_clean
GROUP BY shipping_mode
ORDER BY avg_gap_days DESC;


-- ------------------------------------------------------------
-- Q4: Does delivery delay correlate with order profitability?
--     Are we losing money specifically on late orders?
-- ------------------------------------------------------------
SELECT
    CASE WHEN late_delivery_risk = 1 THEN 'Late' ELSE 'On Time/Early' END AS delivery_group,
    COUNT(*)                                    AS total_orders,
    ROUND(AVG(benefit_per_order), 2)            AS avg_benefit_per_order,
    ROUND(AVG(order_item_profit_ratio), 4)      AS avg_profit_ratio,
    ROUND(AVG(sales), 2)                        AS avg_sales
FROM orders_clean
GROUP BY delivery_group;

-- ============================================================
-- Step 4B: Profitability & Sales
-- Source table: orders_clean
-- ============================================================

USE supply_chain_analysis;

-- ------------------------------------------------------------
-- Q5: Which product categories/departments generate the highest
--     sales but the lowest profit ratio (high revenue, poor margin)?
--
-- Business context: total sales alone can be misleading -- a
-- category can look like a top performer by revenue while quietly
-- destroying margin. Ranking both metrics side by side surfaces
-- categories that need a pricing/cost review.
-- ------------------------------------------------------------
SELECT
    category_name,
    department_name,
    COUNT(*)                                AS total_order_items,
    ROUND(SUM(sales), 2)                    AS total_sales,
    ROUND(AVG(order_item_profit_ratio), 4)  AS avg_profit_ratio,
    ROUND(SUM(order_profit_per_order), 2)   AS total_profit
FROM orders_clean
GROUP BY category_name, department_name
ORDER BY total_sales DESC;


-- ------------------------------------------------------------
-- Q6: Which customer segment is most profitable PER ORDER,
--     not just highest in total volume?
--
-- Business context: distinguishes "biggest segment" from "most
-- efficient/profitable segment" -- a segment can have fewer
-- orders but higher average profitability per order.
-- ------------------------------------------------------------
SELECT
    customer_segment,
    COUNT(DISTINCT order_id)                AS total_orders,
    ROUND(SUM(sales), 2)                    AS total_sales,
    ROUND(SUM(order_profit_per_order), 2)   AS total_profit,
    ROUND(AVG(order_profit_per_order), 2)   AS avg_profit_per_order_item,
    ROUND(AVG(order_item_profit_ratio), 4)  AS avg_profit_ratio
FROM orders_clean
GROUP BY customer_segment
ORDER BY avg_profit_per_order_item DESC;


-- ------------------------------------------------------------
-- Q7: How does discount rate affect profit ratio -- is there a
--     threshold beyond which orders become unprofitable?
--
-- Business context: bucketing discount rate into ranges lets us
-- see if profit ratio drops sharply past a certain discount level,
-- which would suggest a discounting policy cap is needed.
-- ------------------------------------------------------------
SELECT
    CASE
        WHEN order_item_discount_rate = 0 THEN '0% (No Discount)'
        WHEN order_item_discount_rate <= 0.10 THEN '1-10%'
        WHEN order_item_discount_rate <= 0.20 THEN '11-20%'
        WHEN order_item_discount_rate <= 0.30 THEN '21-30%'
        ELSE '31%+'
    END AS discount_bucket,
    COUNT(*)                                AS total_order_items,
    ROUND(AVG(order_item_profit_ratio), 4)  AS avg_profit_ratio,
    ROUND(AVG(order_profit_per_order), 2)   AS avg_profit_per_order_item
FROM orders_clean
GROUP BY discount_bucket
ORDER BY discount_bucket;


-- ------------------------------------------------------------
-- Q8: Which regions/markets are net loss-making despite having
--     decent sales volume?
--
-- Business context: flips the usual "top region by sales" view --
-- specifically surfaces regions where total_profit is negative,
-- regardless of how much revenue they generate.
-- ------------------------------------------------------------
SELECT
    market,
    order_region,
    COUNT(*)                                AS total_order_items,
    ROUND(SUM(sales), 2)                    AS total_sales,
    ROUND(SUM(order_profit_per_order), 2)   AS total_profit
FROM orders_clean
GROUP BY market, order_region
HAVING SUM(order_profit_per_order) < 0
ORDER BY total_profit ASC;

-- ============================================================
-- Step 4C: Customer Behavior & Segmentation
-- Source table: orders_clean
-- ============================================================

USE supply_chain_analysis;

-- ------------------------------------------------------------
-- Q9: Who are the top 10% customers by revenue, and what % of
--     total sales do they contribute? (Pareto / 80-20 check)
--
-- Business context: classic Pareto analysis -- tests whether a
-- small group of customers drives a disproportionate share of
-- revenue, which shapes retention/loyalty strategy priorities.
-- ------------------------------------------------------------
WITH customer_sales AS (
    SELECT
        customer_id,
        SUM(sales) AS total_customer_sales
    FROM orders_clean
    GROUP BY customer_id
),
ranked_customers AS (
    SELECT
        customer_id,
        total_customer_sales,
        NTILE(10) OVER (ORDER BY total_customer_sales DESC) AS decile
    FROM customer_sales
)
SELECT
    (SELECT SUM(total_customer_sales) FROM ranked_customers WHERE decile = 1) AS top_10pct_sales,
    (SELECT SUM(total_customer_sales) FROM ranked_customers)                  AS total_sales_all_customers,
    ROUND(
        (SELECT SUM(total_customer_sales) FROM ranked_customers WHERE decile = 1) * 100.0
        / (SELECT SUM(total_customer_sales) FROM ranked_customers), 2
    ) AS top_10pct_sales_share_pct;


-- ------------------------------------------------------------
-- Q10: Do Corporate/Home Office customers order differently
--      (basket size, frequency) compared to Consumer segment?
--
-- Business context: compares average order value and item
-- quantity across segments -- informs whether B2B-style segments
-- (Corporate/Home Office) genuinely behave differently from
-- individual consumers, or if segmentation is more of a label
-- than a real behavioral difference.
-- ------------------------------------------------------------
SELECT
    customer_segment,
    COUNT(DISTINCT order_id)                          AS total_orders,
    COUNT(DISTINCT customer_id)                        AS total_customers,
    ROUND(COUNT(*) * 1.0 / COUNT(DISTINCT order_id), 2) AS avg_items_per_order,
    ROUND(AVG(order_item_quantity), 2)                  AS avg_quantity_per_item,
    ROUND(SUM(sales) / COUNT(DISTINCT order_id), 2)     AS avg_order_value
FROM orders_clean
GROUP BY customer_segment
ORDER BY avg_order_value DESC;

-- ============================================================
-- Step 4D: Order & Fraud/Risk Patterns
-- Source table: orders_clean
-- ============================================================

USE supply_chain_analysis;

-- ------------------------------------------------------------
-- Q12: What is the distribution of Order Status, and which
--      regions/segments show disproportionately high fraud/
--      cancellation rates?
--
-- Business context: first establishes the overall status
-- breakdown, then narrows in on SUSPECTED_FRAUD and CANCELED
-- specifically by region/segment to spot concentration patterns
-- worth investigating operationally.
-- ------------------------------------------------------------

-- Overall order status distribution
SELECT
    order_status,
    COUNT(*)                                        AS total_order_items,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM orders_clean), 2) AS pct_of_total
FROM orders_clean
GROUP BY order_status
ORDER BY total_order_items DESC;

-- Suspected fraud / canceled rate by market and region
SELECT
    market,
    order_region,
    COUNT(*)                                                                        AS total_order_items,
    SUM(CASE WHEN order_status = 'SUSPECTED_FRAUD' THEN 1 ELSE 0 END)                AS suspected_fraud_count,
    ROUND(SUM(CASE WHEN order_status = 'SUSPECTED_FRAUD' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS fraud_pct,
    SUM(CASE WHEN order_status = 'CANCELED' THEN 1 ELSE 0 END)                       AS canceled_count,
    ROUND(SUM(CASE WHEN order_status = 'CANCELED' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS canceled_pct
FROM orders_clean
GROUP BY market, order_region
HAVING COUNT(*) >= 100
ORDER BY fraud_pct DESC;

-- Suspected fraud / canceled rate by customer segment
SELECT
    customer_segment,
    COUNT(*)                                                                        AS total_order_items,
    SUM(CASE WHEN order_status = 'SUSPECTED_FRAUD' THEN 1 ELSE 0 END)                AS suspected_fraud_count,
    ROUND(SUM(CASE WHEN order_status = 'SUSPECTED_FRAUD' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS fraud_pct,
    SUM(CASE WHEN order_status = 'CANCELED' THEN 1 ELSE 0 END)                       AS canceled_count,
    ROUND(SUM(CASE WHEN order_status = 'CANCELED' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS canceled_pct
FROM orders_clean
GROUP BY customer_segment
ORDER BY fraud_pct DESC;


-- ------------------------------------------------------------
-- Q13: Is there a relationship between high discount rates and
--      suspected fraud orders?
--
-- Business context: tests a well-known retail fraud pattern --
-- fraudulent transactions often exploit high discounts or
-- promotional abuse. Reuses the same discount bucket logic
-- from Q7 for consistency.
-- ------------------------------------------------------------
SELECT
    CASE
        WHEN order_item_discount_rate = 0 THEN '0% (No Discount)'
        WHEN order_item_discount_rate <= 0.10 THEN '1-10%'
        WHEN order_item_discount_rate <= 0.20 THEN '11-20%'
        WHEN order_item_discount_rate <= 0.30 THEN '21-30%'
        ELSE '31%+'
    END AS discount_bucket,
    COUNT(*)                                                            AS total_order_items,
    SUM(CASE WHEN order_status = 'SUSPECTED_FRAUD' THEN 1 ELSE 0 END)    AS suspected_fraud_count,
    ROUND(SUM(CASE WHEN order_status = 'SUSPECTED_FRAUD' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS fraud_pct
FROM orders_clean
GROUP BY discount_bucket
ORDER BY discount_bucket;


-- ------------------------------------------------------------
-- Q14: Which product categories are most frequently canceled or
--      put on payment review (PENDING_PAYMENT)?
--
-- Business context: surfaces specific categories with unusually
-- high friction in the order fulfillment process -- could point
-- to product-specific issues (e.g., high-value items triggering
-- more payment verification, or specific categories prone to
-- cancellation).
-- ------------------------------------------------------------
SELECT
    category_name,
    COUNT(*)                                                                       AS total_order_items,
    SUM(CASE WHEN order_status = 'CANCELED' THEN 1 ELSE 0 END)                      AS canceled_count,
    ROUND(SUM(CASE WHEN order_status = 'CANCELED' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS canceled_pct,
    SUM(CASE WHEN order_status = 'PENDING_PAYMENT' THEN 1 ELSE 0 END)                AS pending_payment_count,
    ROUND(SUM(CASE WHEN order_status = 'PENDING_PAYMENT' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS pending_payment_pct
FROM orders_clean
GROUP BY category_name
HAVING COUNT(*) >= 100
ORDER BY canceled_pct DESC;


-- ------------------------------------------------------------
-- Q11: Which cities/states/countries show the highest customer
--      concentration, and is our shipping performance consistent
--      there?
--
-- Business context: identifies where the customer base is
-- geographically concentrated, then checks whether that
-- concentration correlates with better or worse delivery
-- performance -- useful for prioritizing logistics investment.
-- ------------------------------------------------------------
SELECT
    customer_country,
    customer_state,
    customer_city,
    COUNT(DISTINCT customer_id)                          AS distinct_customers,
    COUNT(*)                                             AS total_order_items,
    ROUND(SUM(late_delivery_risk) * 100.0 / COUNT(*), 2) AS late_delivery_pct
FROM orders_clean
GROUP BY customer_country, customer_state, customer_city
HAVING COUNT(DISTINCT customer_id) >= 20   -- filters out cities with too few customers to be meaningful
ORDER BY distinct_customers DESC
LIMIT 20;

-- ============================================================
-- Step 4E: Product Performance
-- Source table: orders_clean
-- ============================================================

USE supply_chain_analysis;

-- ------------------------------------------------------------
-- Q15: Which are the top and bottom 10 products by total profit
--      contributed (not just sales)?
--
-- Business context: ranks products by actual profit contribution
-- rather than revenue -- surfaces genuinely valuable products vs.
-- ones that just look big on a sales report but contribute little
-- (or negative) profit.
-- ------------------------------------------------------------

-- Top 10 products by total profit
SELECT
    product_name,
    category_name,
    COUNT(*)                                AS total_order_items,
    ROUND(SUM(sales), 2)                    AS total_sales,
    ROUND(SUM(order_profit_per_order), 2)   AS total_profit,
    ROUND(AVG(order_item_profit_ratio), 4)  AS avg_profit_ratio
FROM orders_clean
GROUP BY product_name, category_name
ORDER BY total_profit DESC
LIMIT 10;

-- Bottom 10 products by total profit (biggest loss-makers)
SELECT
    product_name,
    category_name,
    COUNT(*)                                AS total_order_items,
    ROUND(SUM(sales), 2)                    AS total_sales,
    ROUND(SUM(order_profit_per_order), 2)   AS total_profit,
    ROUND(AVG(order_item_profit_ratio), 4)  AS avg_profit_ratio
FROM orders_clean
GROUP BY product_name, category_name
ORDER BY total_profit ASC
LIMIT 10;

-- ============================================================
-- Q16 (Alternate): Same logic, with a looser margin threshold
-- Purpose: Check if any high-volume products show up as
--          borderline-profitable at a slightly higher cutoff
--          than the original 5% threshold
-- ============================================================

USE supply_chain_analysis;

SELECT
    product_name,
    category_name,
    COUNT(*)                                AS total_order_items,
    ROUND(SUM(sales), 2)                    AS total_sales,
    ROUND(AVG(order_item_profit_ratio), 4)  AS avg_profit_ratio,
    ROUND(SUM(order_profit_per_order), 2)   AS total_profit
FROM orders_clean
GROUP BY product_name, category_name
HAVING SUM(sales) > (SELECT AVG(product_total_sales) FROM (
                        SELECT SUM(sales) AS product_total_sales
                        FROM orders_clean
                        GROUP BY product_name
                     ) AS product_sales_avg)
   AND AVG(order_item_profit_ratio) <= 0.15   -- loosened from 0.05 to 0.15
ORDER BY avg_profit_ratio ASC;

-- ============================================================
-- Step 4F: Web Access Log Analysis
-- Source tables: access_logs_raw, orders_clean
-- ============================================================

USE supply_chain_analysis;

-- ------------------------------------------------------------
-- Q17: Is there a relationship between browsing activity (access
--      logs) and actual order volume/timing -- do access spikes
--      precede or align with order spikes?
--
-- Business context: aggregates both browsing and order activity
-- by month, restricted to the overlapping window both tables
-- actually share (2017-09-01 to 2018-01-31), so we're not
-- comparing periods where one dataset simply has no data.
-- ------------------------------------------------------------

-- Monthly browsing activity (access_logs_raw)
SELECT
    DATE_FORMAT(log_date, '%Y-%m') AS activity_month,
    COUNT(*)                       AS total_page_views
FROM access_logs_raw
GROUP BY activity_month
ORDER BY activity_month;

-- Monthly order activity (orders_clean), restricted to the same overlapping window
SELECT
    DATE_FORMAT(order_date, '%Y-%m') AS activity_month,
    COUNT(*)                          AS total_order_items,
    ROUND(SUM(sales), 2)              AS total_sales
FROM orders_clean
WHERE order_date >= '2017-09-01' AND order_date <= '2018-01-31'
GROUP BY activity_month
ORDER BY activity_month;


-- ------------------------------------------------------------
-- Q18: Can we identify patterns in access log activity by
--      product/category that align with or diverge from order
--      patterns -- e.g., high traffic, low conversion?
--
-- Business context: joins aggregated browsing counts to
-- aggregated order counts at the product level (using LEFT JOIN
-- so unmatched products, per our Step 3B finding, still appear
-- with NULL order data rather than being silently dropped),
-- restricted to the same overlapping time window for fairness.
-- A simple "views per order" ratio approximates conversion
-- efficiency -- not a true conversion rate, since we cannot
-- track individual browsing sessions to individual orders.
-- ------------------------------------------------------------
WITH browsing_activity AS (
    SELECT
        TRIM(product) AS product_name_trimmed,
        COUNT(*)       AS total_page_views
    FROM access_logs_raw
    GROUP BY TRIM(product)
),
order_activity AS (
    SELECT
        TRIM(product_name) AS product_name_trimmed,
        COUNT(*)           AS total_order_items,
        ROUND(SUM(sales), 2) AS total_sales
    FROM orders_clean
    WHERE order_date >= '2017-09-01' AND order_date <= '2018-01-31'
    GROUP BY TRIM(product_name)
)
SELECT
    b.product_name_trimmed                              AS product_name,
    b.total_page_views,
    COALESCE(o.total_order_items, 0)                     AS total_order_items,
    COALESCE(o.total_sales, 0)                           AS total_sales,
    ROUND(b.total_page_views * 1.0 / NULLIF(o.total_order_items, 0), 2) AS views_per_order
FROM browsing_activity b
LEFT JOIN order_activity o ON b.product_name_trimmed = o.product_name_trimmed
ORDER BY b.total_page_views DESC;

-- ============================================================
-- Q8 (Visualization version): Same logic as before, but WITHOUT
-- the HAVING < 0 filter -- shows all markets/regions and their
-- profit, so the "no region is unprofitable" finding can be
-- shown visually rather than just stated as a zero-result
-- ============================================================

USE supply_chain_analysis;

SELECT
    market,
    order_region,
    COUNT(*)                                AS total_order_items,
    ROUND(SUM(sales), 2)                    AS total_sales,
    ROUND(SUM(order_profit_per_order), 2)   AS total_profit
FROM orders_clean
GROUP BY market, order_region
ORDER BY total_profit ASC;

-- ============================================================
-- Check what customer_country values actually exist in orders_clean
-- Purpose: Confirm whether non-English/abbreviated country names
--          (e.g. "EE. UU." for USA) are breaking Tableau's
--          geographic role recognition on the Q11 map
-- ============================================================
USE supply_chain_analysis;

SELECT DISTINCT customer_country, COUNT(*) AS row_count
FROM orders_clean
GROUP BY customer_country
ORDER BY row_count DESC;

-- ============================================================
-- Q11 (Corrected): Standardize customer_country to English names
-- Purpose: "EE. UU." (Spanish abbreviation for USA) and any other
--          non-English country values break Tableau's geographic
--          role recognition -- standardizing here fixes mapping
-- ============================================================
SELECT
    CASE
        WHEN customer_country = 'EE. UU.' THEN 'United States'
        ELSE customer_country
    END AS customer_country,
    customer_state,
    customer_city,
    COUNT(DISTINCT customer_id)                          AS distinct_customers,
    COUNT(*)                                             AS total_order_items,
    ROUND(SUM(late_delivery_risk) * 100.0 / COUNT(*), 2) AS late_delivery_pct
FROM orders_clean
GROUP BY customer_country, customer_state, customer_city
HAVING COUNT(DISTINCT customer_id) >= 20
ORDER BY distinct_customers DESC
LIMIT 20;

-- ============================================================
-- Check the actual distribution of views_per_order to set a
-- meaningful, data-driven threshold instead of an arbitrary guess
-- ============================================================
USE supply_chain_analysis;

SELECT
    MIN(views_per_order)              AS min_views_per_order,
    MAX(views_per_order)              AS max_views_per_order,
    AVG(views_per_order)              AS avg_views_per_order,
    -- Approximate median using a simple ordered approach since MySQL lacks a native MEDIAN function
    (SELECT views_per_order
     FROM (
        SELECT views_per_order, ROW_NUMBER() OVER (ORDER BY views_per_order) AS rn,
               COUNT(*) OVER () AS total_rows
        FROM (
            SELECT product, views_per_order
            FROM (SELECT product_name AS product, 
                         (SELECT total_page_views FROM ) AS dummy -- placeholder, replaced below
                  FROM orders_clean LIMIT 0) x
        ) y
     ) z
     WHERE rn = FLOOR(total_rows/2)
    ) AS median_placeholder
FROM (SELECT 1) dummy_table;