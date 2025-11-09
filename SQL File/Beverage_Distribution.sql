/*======================================================================*
    Beverage Distribution
 *======================================================================*/

/*======================================================================*
  0. BOOTSTRAP
 *======================================================================*/
-- CREATE AND SELECT DATABASE
CREATE DATABASE IF NOT EXISTS BEVARAGES;
USE BEVARAGES;

SET sql_safe_updates = 0;
SET sql_safe_updates = 1;
/*======================================================================*
  1. DATA PREPATION  (VALIDATION & CLEANING)
 *======================================================================*/
-- 1.1 Row counts per table (sanity check)

SELECT 'Customers' Table_Names, COUNT(*) No_of_Rows_Count FROM Customers
UNION ALL SELECT 'Suppliers', COUNT(*) FROM Suppliers
UNION ALL SELECT 'Branches', COUNT(*) FROM NO_OF_Branches
UNION ALL SELECT 'Employees', COUNT(*) FROM employees
UNION ALL SELECT 'Products', COUNT(*) FROM Products
UNION ALL SELECT 'Orders', COUNT(*) FROM Orders
UNION ALL SELECT 'Sales', COUNT(*) FROM Sales
UNION ALL SELECT 'Payments', COUNT(*) FROM Payments;

-- 1.2 Check for NULL values, blank values (''), and duplicates in all tables
SELECT
	count(*) AS No_of_Rows_Count,
    COUNT(CASE WHEN EmployeeID = '' THEN 1 END) AS Blank_EmployeeIDs,
    COUNT(CASE WHEN EmployeeID IS NULL THEN 1 END) AS Null_EmployeeIDs,
    COUNT(CASE WHEN EmployeeID IS NOT NULL AND EmployeeID <> '' THEN 1 END) AS Filled_EmployeeIDs
FROM salestargets;
UPDATE salestargets s
JOIN employees e ON s.BranchID = e.BranchID
SET s.EmployeeID = e.EmployeeID
WHERE s.EmployeeID = '';
UPDATE salestargets SET EmployeeID = NULL WHERE EmployeeID = '';

SELECT
    COUNT(*) AS Total_Rows,
    COUNT(CASE WHEN ProductID IS NULL OR ProductID = '' THEN 1 END) AS Null_Blank_ProductID,
    COUNT(CASE WHEN BrandFamily IS NULL OR BrandFamily = '' THEN 1 END) AS Null_Blank_BrandFamily,
    COUNT(CASE WHEN ProductName IS NULL OR ProductName = '' THEN 1 END) AS Null_Blank_ProductName,
    COUNT(CASE WHEN Container IS NULL OR Container = '' THEN 1 END) AS Null_Blank_Container,
    COUNT(CASE WHEN DefaultSupplier IS NULL OR DefaultSupplier = '' THEN 1 END) AS Null_Blank_DefaultSupplier
FROM PRODUCTS;
-- duplicates VALUES FOUND
SELECT CustomerID,COUNT(CustomerID) FROM CUSTOMERS
GROUP BY CustomerID HAVING COUNT(CustomerID) > 1;
SELECT ShopName,COUNT(ShopName) FROM CUSTOMERS
GROUP BY ShopName HAVING COUNT(ShopName) > 1;

-- 1.3 Assign both Primary Key (PK) and Foreign Key (FK) constraints for each table
-- Primary Keys
ALTER TABLE customers        ADD PRIMARY KEY (CustomerID);
ALTER TABLE suppliers        ADD PRIMARY KEY (SupplierID);
ALTER TABLE no_of_branches   ADD PRIMARY KEY (BranchID);
ALTER TABLE employees        ADD PRIMARY KEY (EmployeeID);
ALTER TABLE products         ADD PRIMARY KEY (ProductID);
ALTER TABLE payments         ADD PRIMARY KEY (PaymentID);
ALTER TABLE inventoryledger  ADD PRIMARY KEY (LedgerID);
ALTER TABLE deliveries       ADD PRIMARY KEY (DeliveryID);
ALTER TABLE expenses         ADD PRIMARY KEY (ExpenseID);
ALTER TABLE salestargets     ADD PRIMARY KEY (TargetID);

-- Orders Table (PK + all FKs)
ALTER TABLE orders
ADD PRIMARY KEY (OrderID),
ADD CONSTRAINT fk_order_customer FOREIGN KEY(CustomerID) REFERENCES customers(CustomerID),
ADD CONSTRAINT fk_order_branch   FOREIGN KEY(BranchID) REFERENCES no_of_branches(BranchID),
ADD CONSTRAINT fk_order_employee FOREIGN KEY(EmployeeID) REFERENCES employees(EmployeeID);

-- Sales Table (PK + all FKs)
ALTER TABLE sales
ADD PRIMARY KEY (SalesID),
ADD CONSTRAINT fk_sales_order     FOREIGN KEY(OrderID)    REFERENCES orders(OrderID),
ADD CONSTRAINT fk_sales_product   FOREIGN KEY(ProductID)  REFERENCES products(ProductID),
ADD CONSTRAINT fk_sales_supplier  FOREIGN KEY(SupplierID) REFERENCES suppliers(SupplierID);

-- Returns Table
ALTER TABLE returns
ADD PRIMARY KEY (ReturnID),
ADD CONSTRAINT fk_returns_sales FOREIGN KEY(SalesID) REFERENCES sales(SalesID);

--  Sales without matching Order
SELECT s.salesID FROM sales s
LEFT JOIN products p ON p.productid = s.productid
WHERE p.productid IS NULL;

-- Orders with missing Customer
SELECT o.OrderID
FROM Orders o LEFT JOIN Customers c ON c.CustomerID = o.CustomerID
WHERE o.CustomerID IS NULL;

-- 1.4 Date consistency: payments shouldn't predate orders
select p.OrderID,p.PaymentDate,o.OrderDateTime from payments p
left join orders o on p.OrderID = o.OrderID
where p.PaymentDate < o.OrderDateTime
order by o.OrderDateTime desc;

/*======================================================================*
  2. DATA MODELLING (RELATIONSHIPS & ANALYTICAL VIEWS)
 *======================================================================*/
 
-- 2.1 Helpful Indexes for joins (safe even if duplicates exist)
CREATE INDEX idx_orders_customer 	ON Orders(CustomerID);
CREATE INDEX idx_orders_branch    	ON orders(BranchID);
CREATE INDEX idx_orders_employee  	ON orders(EmployeeID);
CREATE INDEX idx_orders_datetime  	ON orders(OrderDateTime);
CREATE INDEX idx_sales_order	  	ON sales(OrderID);
CREATE INDEX idx_sales_product	 	ON sales(ProductID);
CREATE INDEX idx_sales_supplier	  	ON sales(SupplierID);
CREATE INDEX idx_payment_payment	ON payments(PaymentID);
CREATE INDEX idx_payments_Date		ON payments(PaymentDate);

-- 2.2 Analytical Views
CREATE OR REPLACE VIEW vSalesOrders AS														
SELECT 
	o.OrderID,
    o.OrderDateTime,
    o.CustomerID,
    o.BranchID,
    o.EmployeeID,
    s.ProductID,
    s.SupplierID,
    s.Quantity,
    s.UnitPrice,
    s.DiscountPct,
    s.TaxPct,
    s.LineTotal
    from orders o
    join sales s on o.OrderID = s.OrderID;

CREATE OR REPLACE VIEW vPaymentsOrders AS
SELECT 
    P.PaymentID,
    P.OrderID,
    P.PaymentDate,
    P.AmountINR,
    P.Mode,
    O.OrderDateTime,
    O.CustomerID,
    O.BranchID,
    O.EmployeeID,
    O.OrderStatus
    FROM payments p
    JOIN orders o ON P.OrderID = O.OrderID;

CREATE OR REPLACE VIEW vOrderTotals AS
SELECT
  o.OrderID,
  o.OrderDateTime,
  o.CustomerID,
  o.BranchID,
  SUM(s.UnitPrice * s.Quantity) AS GrossBeforeDiscount,
  SUM((s.UnitPrice * s.Quantity) * (s.DiscountPct/100)) AS TotalDiscount,
  SUM((s.UnitPrice * s.Quantity) - (s.UnitPrice * s.Quantity) * (s.DiscountPct/100)) AS TaxableValue,
  SUM(((s.UnitPrice * s.Quantity) - (s.UnitPrice * s.Quantity) * (s.DiscountPct/100)) * (s.TaxPct/100)) AS TaxAmount,
  SUM(s.LineTotal) AS OrderTotal
FROM Orders o
JOIN Sales s ON s.OrderID = o.OrderID
GROUP BY o.OrderID, o.OrderDateTime, o.CustomerID, o.BranchID;

CREATE VIEW margin AS
SELECT 
    s.SalesID,
    s.Quantity,
    s.UnitPrice,
    s.LineTotal,
    p.PaymentID,
    p.AmountINR,
    (p.AmountINR - s.LineTotal) AS MarginAmount,
    p.Mode,
    p.Status
FROM Sales AS s
JOIN Payments AS p 
    ON p.OrderID = s.OrderID;

/*======================================================================*
  3. DATA ANALYSIS (INSIGHTS FOR MANAGEMENT)
 *======================================================================*/

-- 3.1 Monthly sales by trend 
select * from vsalesorders;
SELECT date_format(OrderDateTime, '%y-%m') AS Year_Mounth, sum(LineTotal) AS sales
FROM vSalesOrders
GROUP BY 1
ORDER BY 1;
select * from vsalesorders;
-- 3.2 Orders by Sales
select OrderID, round(sum(LineTotal),2) as sales from vsalesorders
group by OrderID
order by sales desc limit 50;

-- 3.3 Branch Performance
SELECT b.BranchID,b.BranchName, sum(vs.LineTotal) AS total_sale 
FROM no_of_branches b 
JOIN vSalesOrders vs ON vs.BranchID = b.BranchID
GROUP BY b.BranchID,b.BranchName
ORDER BY total_sale DESC LIMIT 50;

-- 3.4 Top 10 customers based on sales
SELECT c.CustomerID, c.CustomerName, sum(vs.LineTotal) AS total_sales from customers c
JOIN vSalesOrders vs ON c.CustomerID = vs.CustomerID
GROUP BY c.CustomerID, c.CustomerName
ORDER BY total_sales DESC LIMIT 10;

-- 3.5 Product Category Mix
SELECT p.Category, round(sum(LineTotal),2) AS sale FROM vSalesOrders vs
JOIN products p ON p.ProductID = vs.ProductID
GROUP BY p.Category
ORDER BY sale DESC;

-- 3.6 GST Amount by category
SELECT P.Category,
	 round(sum((vs.UnitPrice * vs.Quantity) * (1 -vs.DiscountPct/100) * (vs.TaxPct/100)),2) AS GST_Amount
FROM vSalesOrders vs
JOIN products p ON vs.ProductID = p.ProductID
GROUP BY P.Category
ORDER BY GST_Amount desc;

-- 3.7 Receivables Aging
SELECT
  CASE
    WHEN DATEDIFF(CURDATE(), DATE(t.OrderDateTime)) <= 30 THEN '0-30'
    WHEN DATEDIFF(CURDATE(), DATE(t.OrderDateTime)) <= 60 THEN '31-60'
    WHEN DATEDIFF(CURDATE(), DATE(t.OrderDateTime)) <= 90 THEN '61-90'
    ELSE '90+'
  END AS AgingBucket,
  round(SUM(t.OrderTotal - COALESCE(p.Paid,0)),2) AS Outstanding
FROM vOrderTotals t
LEFT JOIN (
  SELECT OrderID, round(SUM(AmountINR),2) AS Paid
  FROM Payments
  WHERE Status IN ('Captured','Partial','Refunded') 
  GROUP BY OrderID
) p ON p.OrderID = t.OrderID
GROUP BY AgingBucket
ORDER BY MIN(DATEDIFF(CURDATE(), DATE(t.OrderDateTime)));

-- 3.8 Discount Bands Impact
SELECT 
	CASE
		WHEN vs.DiscountPct = 0 THEN '0%'
		WHEN vs.DiscountPct <= 3 THEN '0-3%'
		WHEN vs.DiscountPct <= 5 THEN '3-5%'
        ELSE '5%+' 
        END AS DISBAND,
        ROUND(sum(vs.LineTotal),2) AS Sales
        FROM vsalesorders VS
GROUP BY DISBAND
ORDER BY Sales DESC;

-- 3.9 Fast-Moving SKUs (by Quantity)
SELECT p.ProductName,p.SizeML,p.Container, sum(sv.Quantity) AS qty FROM vsalesorders sv
	JOIN products p ON p.ProductID = sv.ProductID
    GROUP BY p.ProductName,p.SizeML,p.Container
    ORDER BY qty DESC;

-- 3.10 Collection by Payment Mode
SELECT mode, round(sum(AmountINR),2) AS Amount FROM payments
WHERE STATUS IN ('Captured','Partial','Refunded')
GROUP BY mode
ORDER BY Amount DESC;

/*======================================================================*
  4. PRESENTATION (EXPORT & BI FEEDS)
 *======================================================================*/

-- 4.1 Feed for Sales Dashboard (trend + branch + brand)
-- Trend
SELECT DATE_FORMAT(OrderDateTime, '%Y-%m') AS YearMonth, round(SUM(LineTotal),2) AS Sales
FROM vsalesorders GROUP BY 1 ORDER BY 1;

-- Branch
SELECT b.BranchName, ROUND(SUM(s.LineTotal),2) AS Sales FROM no_of_branches b 
LEFT JOIN orders o ON b.BranchID = o.BranchID
LEFT JOIN sales s ON s.OrderID = o.OrderID
GROUP BY b.BranchName
ORDER BY Sales DESC;
-- BrandFamily Ratio
SELECT p.brandfamily, round(sum(s.linetotal),2) AS sale FROM products p
JOIN sales s on p.ProductID = s.ProductID
group by p.brandfamily
order by sale desc;
-- 4.2 Feed for Operations Dashboard (Order Status)
SELECT OrderStatus, COUNT(*) AS Orders FROM Orders GROUP BY OrderStatus;

-- 4.3 Customer Insights
SELECT c.CustomerID, c.CustomerName, c.Area, ROUND(SUM(sf.LineTotal),2) AS Revenue
FROM vsalesorders sf JOIN Customers c ON c.CustomerID = sf.CustomerID
GROUP BY c.CustomerID, c.CustomerName, c.Area
ORDER BY Revenue DESC limit 20;

/*======================================================================*
  5. IMPROVEMENTS (OPTIMIZATION & AUTOMATION)
 *======================================================================*/

-- 5.1 Monthly Sales Summary Stored Procedure
DELIMITER //
CREATE PROCEDURE sp_MonthlySalesSummary()
BEGIN
  SELECT DATE_FORMAT(OrderDateTime, '%Y-%m') AS Month,
         SUM(LineTotal) AS TotalSales,
         COUNT(DISTINCT CustomerID) AS Customers,
         COUNT(DISTINCT ProductID) AS SKUs
  FROM vsalesorders
  GROUP BY 1
  ORDER BY 1;
END //
DELIMITER ;

CALL sp_MonthlySalesSummary();

-- 5.2 Data quality checks as a view
CREATE OR REPLACE VIEW vDataQuality_Issues AS
SELECT 'Payment before Order' AS Issue, p.OrderID AS RefID
FROM Payments p JOIN Orders o ON o.OrderID = p.OrderID
WHERE p.PaymentDate < o.OrderDateTime
UNION ALL
SELECT 'Sales without Product', s.SalesID
FROM Sales s LEFT JOIN Products p2 ON p2.ProductID = s.ProductID
WHERE p2.ProductID IS NULL
UNION ALL
SELECT 'Order without Customer', o.OrderID
FROM Orders o LEFT JOIN Customers c2 ON c2.CustomerID = o.CustomerID
WHERE c2.CustomerID IS NULL;

SELECT @@hostname AS ServerName;

SELECT @@version AS Version,
       @@version_comment AS VersionComment,
       @@hostname AS HostName,
       @@port AS Port;

