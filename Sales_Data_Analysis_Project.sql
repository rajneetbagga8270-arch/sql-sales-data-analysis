-- SQL DATA ANALYSIS PROJECT
-- MySQL | Sales Analytics

CREATE DATABASE IF NOT EXISTS sales_analytics;
USE sales_analytics;

DROP TABLE IF EXISTS sales_raw;
CREATE TABLE sales_raw (
    order_id VARCHAR(20),
    order_date DATE,
    customer_id VARCHAR(20),
    region VARCHAR(50),
    city VARCHAR(80),
    product VARCHAR(100),
    category VARCHAR(80),
    quantity INT,
    unit_price DECIMAL(10,2),
    discount DECIMAL(5,2)
);

-- Import sql_sales_raw_data.csv into sales_raw using MySQL Workbench:
-- Right-click the database > Table Data Import Wizard.

-- DATA CLEANING
DROP TABLE IF EXISTS sales_clean;
CREATE TABLE sales_clean AS
SELECT
    TRIM(order_id) AS order_id,
    order_date,
    TRIM(customer_id) AS customer_id,
    TRIM(UPPER(region)) AS region,
    TRIM(city) AS city,
    TRIM(product) AS product,
    TRIM(category) AS category,
    COALESCE(quantity, 1) AS quantity,
    unit_price,
    COALESCE(discount, 0) AS discount
FROM sales_raw;

-- Check duplicates
SELECT order_id, COUNT(*) AS duplicate_count
FROM sales_clean
GROUP BY order_id
HAVING COUNT(*) > 1;

-- Check missing values
SELECT
    SUM(order_id IS NULL) AS missing_order_id,
    SUM(customer_id IS NULL) AS missing_customer_id,
    SUM(quantity IS NULL) AS missing_quantity,
    SUM(unit_price IS NULL) AS missing_unit_price
FROM sales_clean;

-- ANALYTICAL VIEW
CREATE OR REPLACE VIEW sales_analysis AS
SELECT
    order_id, order_date, customer_id, region, city, product, category,
    quantity, unit_price, discount,
    quantity * unit_price AS gross_sales,
    quantity * unit_price * discount AS discount_amount,
    quantity * unit_price * (1 - discount) AS net_sales
FROM sales_clean;

-- 1. Overall KPIs
SELECT
    COUNT(DISTINCT order_id) AS total_orders,
    COUNT(DISTINCT customer_id) AS total_customers,
    SUM(quantity) AS units_sold,
    ROUND(SUM(net_sales), 2) AS total_revenue,
    ROUND(AVG(net_sales), 2) AS average_order_value
FROM sales_analysis;

-- 2. Revenue by region
SELECT region, ROUND(SUM(net_sales),2) AS revenue,
       SUM(quantity) AS units_sold,
       COUNT(DISTINCT order_id) AS orders
FROM sales_analysis
GROUP BY region
ORDER BY revenue DESC;

-- 3. Revenue by product
SELECT product, category, ROUND(SUM(net_sales),2) AS revenue,
       SUM(quantity) AS units_sold
FROM sales_analysis
GROUP BY product, category
ORDER BY revenue DESC;

-- 4. Revenue by category
SELECT category, ROUND(SUM(net_sales),2) AS revenue
FROM sales_analysis
GROUP BY category
ORDER BY revenue DESC;

-- 5. Monthly revenue
SELECT YEAR(order_date) AS year,
       MONTH(order_date) AS month_number,
       MONTHNAME(order_date) AS month_name,
       ROUND(SUM(net_sales),2) AS revenue
FROM sales_analysis
GROUP BY YEAR(order_date), MONTH(order_date), MONTHNAME(order_date)
ORDER BY year, month_number;

-- 6. Top 5 customers
SELECT customer_id, ROUND(SUM(net_sales),2) AS revenue
FROM sales_analysis
GROUP BY customer_id
ORDER BY revenue DESC
LIMIT 5;

-- JOIN
DROP TABLE IF EXISTS customers;
CREATE TABLE customers AS
SELECT DISTINCT customer_id,
       CONCAT('Customer ', customer_id) AS customer_name
FROM sales_clean;

SELECT s.order_id, s.order_date, c.customer_name,
       s.product, s.region, ROUND(s.net_sales,2) AS net_sales
FROM sales_analysis s
JOIN customers c ON s.customer_id = c.customer_id
ORDER BY s.order_date DESC;

-- CTE: revenue share by region
WITH region_sales AS (
    SELECT region, SUM(net_sales) AS revenue
    FROM sales_analysis
    GROUP BY region
),
total_sales AS (
    SELECT SUM(net_sales) AS total_revenue
    FROM sales_analysis
)
SELECT r.region,
       ROUND(r.revenue,2) AS revenue,
       ROUND(r.revenue / t.total_revenue * 100,2) AS revenue_share_pct
FROM region_sales r
CROSS JOIN total_sales t
ORDER BY revenue DESC;

-- CTE: products above average revenue
WITH product_sales AS (
    SELECT product, SUM(net_sales) AS revenue
    FROM sales_analysis
    GROUP BY product
)
SELECT product, ROUND(revenue,2) AS revenue
FROM product_sales
WHERE revenue > (SELECT AVG(revenue) FROM product_sales)
ORDER BY revenue DESC;

-- WINDOW FUNCTION: product ranking
SELECT product,
       ROUND(SUM(net_sales),2) AS revenue,
       RANK() OVER (ORDER BY SUM(net_sales) DESC) AS revenue_rank
FROM sales_analysis
GROUP BY product;

-- WINDOW FUNCTION: rank within category
SELECT category, product,
       ROUND(SUM(net_sales),2) AS revenue,
       RANK() OVER (
           PARTITION BY category
           ORDER BY SUM(net_sales) DESC
       ) AS category_rank
FROM sales_analysis
GROUP BY category, product;

-- WINDOW FUNCTION: cumulative monthly revenue
WITH monthly_sales AS (
    SELECT YEAR(order_date) AS year,
           MONTH(order_date) AS month_number,
           MONTHNAME(order_date) AS month_name,
           SUM(net_sales) AS revenue
    FROM sales_analysis
    GROUP BY YEAR(order_date), MONTH(order_date), MONTHNAME(order_date)
)
SELECT year, month_number, month_name,
       ROUND(revenue,2) AS monthly_revenue,
       ROUND(SUM(revenue) OVER (
           ORDER BY year, month_number
       ),2) AS cumulative_revenue
FROM monthly_sales
ORDER BY year, month_number;

-- WINDOW FUNCTION: month-over-month growth
WITH monthly_sales AS (
    SELECT YEAR(order_date) AS year,
           MONTH(order_date) AS month_number,
           SUM(net_sales) AS revenue
    FROM sales_analysis
    GROUP BY YEAR(order_date), MONTH(order_date)
),
comparison AS (
    SELECT year, month_number, revenue,
           LAG(revenue) OVER (
               ORDER BY year, month_number
           ) AS previous_month_revenue
    FROM monthly_sales
)
SELECT year, month_number,
       ROUND(revenue,2) AS revenue,
       ROUND(previous_month_revenue,2) AS previous_month_revenue,
       ROUND(
           (revenue - previous_month_revenue)
           / NULLIF(previous_month_revenue,0) * 100, 2
       ) AS mom_growth_pct
FROM comparison
ORDER BY year, month_number;

-- TOP PRODUCT IN EACH REGION
WITH regional_products AS (
    SELECT region, product, SUM(net_sales) AS revenue
    FROM sales_analysis
    GROUP BY region, product
),
ranked AS (
    SELECT region, product, revenue,
           ROW_NUMBER() OVER (
               PARTITION BY region ORDER BY revenue DESC
           ) AS rn
    FROM regional_products
)
SELECT region, product, ROUND(revenue,2) AS revenue
FROM ranked
WHERE rn = 1
ORDER BY region;
