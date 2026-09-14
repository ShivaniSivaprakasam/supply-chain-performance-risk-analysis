# Supply Chain Performance & Risk Analysis — DataCo Global

An end-to-end data analysis project answering 18 real-world business questions across delivery performance, profitability, customer behavior, fraud risk, product performance, and web engagement — using MySQL, Python, and Tableau.

![Tableau](https://img.shields.io/badge/Tableau-Public-E97627?logo=tableau&logoColor=white)
![MySQL](https://img.shields.io/badge/MySQL-Database-4479A1?logo=mysql&logoColor=white)
![Python](https://img.shields.io/badge/Python-Data%20Loading-3776AB?logo=python&logoColor=white)
![Excel](https://img.shields.io/badge/Excel-Data%20Exploration-217346?logo=microsoftexcel&logoColor=white)

---

## Table of Contents
- [Project Overview](#project-overview)
- [Dataset](#dataset)
- [Tools & Technologies](#tools--technologies)
- [Project Workflow](#project-workflow)
- [Business Questions Answered](#business-questions-answered)
- [Data Cleaning & Quality Checks](#data-cleaning--quality-checks)
- [Dashboards](#dashboards)
- [Key Insights](#key-insights)
- [Limitations & Assumptions](#limitations--assumptions)

---

## Project Overview

This project analyzes order-level transaction data and website browsing logs from a global supply chain dataset (DataCo) to answer 18 business questions spanning six functional areas: **delivery logistics, profitability, customer segmentation, fraud/order risk, product performance, and web-to-order conversion**.

The workflow follows a standard analytics pipeline: raw CSV data was loaded and cleaned in **MySQL**, verified through structured data-quality checks, analyzed using SQL (aggregations, window functions, CTEs), and visualized in **Tableau Public** across six themed dashboards. A **Python (pandas + SQLAlchemy)** script was used as a fallback ETL method after encountering `LOAD DATA LOCAL INFILE` permission restrictions in MySQL Workbench — a real troubleshooting step documented as part of the process, not a planned design choice.

## Dataset

- **Source:** DataCo Supply Chain Dataset (publicly available)
- **`orders_raw` / `orders_clean`:** 180,519 order line items (2015–2018) — one row per order item, covering customer, product, shipping, and profitability fields
- **`access_logs_raw`:** Website browsing/access logs (Sept 2017–Jan 2018) — product page views by date, hour, and category

> Note: the two tables do not share a direct key (no common customer/order ID). They were combined only via aggregated product/category name matching for the web-engagement analysis (see [Limitations](#limitations--assumptions)).

## Tools & Technologies

| Tool | Purpose |
|---|---|
| **MySQL** | Data loading, cleaning, schema design, and all analytical queries |
| **Python (pandas, SQLAlchemy, pymysql)** | Fallback ETL pipeline to load CSV data into MySQL |
| **Microsoft Excel** | Initial data exploration and small-scale cross-checks (e.g., product/category name matching) |
| **Tableau Public** | Dashboard design and data visualization |

## Project Workflow

1. **Data Understanding & Documentation** — Reviewed both source tables and the data dictionary; confirmed table grain and checked join feasibility between tables
2. **Data Loading** — Loaded CSVs into MySQL via a Python/SQLAlchemy script after `LOAD DATA LOCAL INFILE` was blocked by client-side restrictions
3. **Data Quality Verification** — Ran systematic checks for nulls, duplicate/redundant columns, numeric outliers, categorical consistency, and cross-table name matching
4. **Data Cleaning** — Built `orders_clean`, a deduplicated, analysis-ready table (dropped 3 confirmed-redundant ID columns, excluded an 86%-null zipcode field, excluded PII columns)
5. **SQL Analysis** — Wrote 18 business-question queries using aggregations, CTEs, and window functions
6. **Visualization Design** — Selected a distinct, purpose-fit chart type for each question (bar, treemap, bullet graph, scatter, dual-axis, symbol map, diverging bar, etc.)
7. **Dashboard Assembly** — Grouped the 18 visualizations into 6 themed dashboards with a consistent color system and a navigable home page

## Business Questions Answered

**Delivery Performance & Logistics**
1. What % of orders are delivered late, and does it vary by shipping mode?
2. Which markets/regions have the worst late-delivery rates?
3. Which shipping modes over-promise vs. under-deliver?
4. Does late delivery correlate with lower order profitability?

**Profitability & Sales**
5. Which categories sell well but generate poor margins?
6. Which customer segment is most profitable per order?
7. How does discount rate affect profit margin?
8. Are any regions net loss-making despite strong sales volume?

**Customer Behavior & Segmentation**
9. What share of revenue comes from the top 10% of customers?
10. Do Corporate/Home Office customers order differently than Consumers?
11. Where are customers most concentrated, and how well are they served?

**Order & Fraud Risk**
12. What does the order status distribution look like, and where is fraud/cancellation concentrated?
13. Does a higher discount rate correlate with higher fraud risk?
14. Which product categories see the most cancellations/payment holds?

**Product Performance**
15. Which products contribute the most (and least) profit?
16. Are any high-selling products barely profitable?

**Web Engagement**
17. Does browsing activity track with actual order volume over time?
18. Which products get high traffic but low order conversion?

## Data Cleaning & Quality Checks

- **Row-level grain confirmed:** one row = one order line item; verified zero duplicate `order_item_id` values across 180,519 rows
- **Redundant columns identified and removed:** `order_customer_id`, `order_item_cardprod_id`, and `product_category_id` were confirmed as exact duplicates of `customer_id`, `product_card_id`, and `category_id` respectively (0 mismatches found)
- **High-null column excluded:** `order_zipcode` was 86.24% null and dropped from analysis rather than imputed
- **PII excluded:** customer email, password, first name, and last name were excluded from all analytical tables; `customer_id` retained as the sole anonymized identifier, consistent with standard data-privacy practice
- **Numeric sanity checks:** confirmed no negative sales, no zero/negative quantities or prices, no discount rate above 100%, no negative shipping-day values
- **Date integrity:** confirmed 0 null order/shipping dates after correcting a date-format parsing issue during the initial load
- **Cross-table matching:** verified which products/categories in the browsing logs had no exact match in the order data — found to be genuine catalog/navigation differences, not a cleaning defect

## Dashboards

### 1. Delivery Performance & Logistics
https://public.tableau.com/app/profile/shivani.sivaprakasam/viz/Book_Dashboard1_17891013407250/Dashboard1

### 2. Profitability & Sales
https://public.tableau.com/app/profile/shivani.sivaprakasam/viz/Book_Dashboard2/Dashboard2

### 3. Customer Behavior & Segmentation
https://public.tableau.com/app/profile/shivani.sivaprakasam/viz/Book_Dashboard3/Dashboard3

### 4. Fraud & Order Risk
https://public.tableau.com/app/profile/shivani.sivaprakasam/viz/Book_Dashboard4/Dashboard4

### 5. Product Performance
https://public.tableau.com/app/profile/shivani.sivaprakasam/viz/Book_Dashboard5/Dashboard5

### 6. Web Engagement & Conversion
https://public.tableau.com/app/profile/shivani.sivaprakasam/viz/Book_Dashboard6/Dashboard6

## Key Insights

- **First Class shipping has a 95.3% late-delivery rate** — the highest of all shipping modes, and notably higher than the supposedly slower Standard Class (38.1%), a counter-intuitive finding worth operational review.
- **No region in the dataset is net loss-making** — every market/region is profitable in aggregate, meaning any margin issues are concentrated at the product/category level, not regional.
- **Discount rate does not push orders into unprofitability** within the observed range (0–30%) — average profit ratio stays positive throughout, though order volume drops sharply above a 10% discount.
- **Suspected fraud rate rises with discount rate**, consistent with common retail fraud patterns.
- **A small number of products show a large gap between browsing interest and actual orders**, with "views per order" ranging from 25 to over 3,600 — a small set of high-traffic, low-conversion products stand out as clear outliers worth investigating.

## Limitations & Assumptions

- `orders_clean` spans 2015–2018, while `access_logs_raw` only covers September 2017–January 2018; all browsing-vs-order comparisons (Q17, Q18) are restricted to this overlapping window and should not be read as reflecting the full order history.
- No direct join key exists between the order data and the browsing logs; the aggregated product/category-name join used for Q17–18 is an approximation, not a session-level or customer-level match.
- 4 of 76 products and 2 of 33 categories in the browsing logs had no exact name match in the order data, most likely reflecting differences between storefront navigation labels and transactional product naming — these are documented, not silently dropped.
- This is a retrospective, descriptive analysis (no predictive modeling or forecasting was in scope).

```

**Author:** Shivani
**Background:** B.Tech Biotechnology graduate transitioning into Data Analytics
