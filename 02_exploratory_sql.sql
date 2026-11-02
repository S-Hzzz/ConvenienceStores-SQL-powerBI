-- =============================================================
-- 便利店經營分析 · 探索性 SQL（MySQL 8.0 語法，全部已實機驗證）
-- 執行順序：先跑 01_ddl_and_load.sql
-- =============================================================
USE conv_store_analytics;

-- ---------- Q1 數據全景 ----------
SELECT COUNT(*)                      AS 訂單行數,
       COUNT(DISTINCT txn_id)        AS 獨立流水數,
       COUNT(DISTINCT txn_date)      AS 營業天數,
       COUNT(DISTINCT store_id)      AS 門店數,
       COUNT(DISTINCT product_id)    AS 商品數,
       SUM(amount)                   AS 總營收,
       SUM(qty)                      AS 總件數,
       ROUND(SUM(amount)/COUNT(DISTINCT txn_id),2) AS 客單價,
       ROUND(SUM(amount)/SUM(qty),2) AS 件均價
FROM fact_sales;

-- ---------- Q2 門店營收 + 毛利（成本取自 dim_product） ----------
SELECT s.store_id, st.store_name,
       COUNT(DISTINCT s.txn_id)                 AS 交易筆數,
       SUM(s.amount)                            AS 營收,
       SUM(s.qty * p.cost_price)                AS 成本,
       SUM(s.amount) - SUM(s.qty * p.cost_price) AS 毛利,
       ROUND((SUM(s.amount)-SUM(s.qty*p.cost_price))/SUM(s.amount)*100,2) AS 毛利率,
       ROUND(SUM(s.amount)/COUNT(DISTINCT s.txn_id),2) AS 客單價
FROM fact_sales s
JOIN dim_product p ON s.product_id = p.product_id
JOIN dim_store   st ON s.store_id = st.store_id
GROUP BY s.store_id, st.store_name
ORDER BY 營收 DESC;

-- ---------- Q3 品類趨勢（營收 / 佔比 / 毛利率） ----------
SELECT p.category,
       SUM(s.amount)                            AS 營收,
       ROUND(SUM(s.amount)*100.0/(SELECT SUM(amount) FROM fact_sales),2) AS 營收佔比_pct,
       SUM(s.qty)                               AS 銷量,
       ROUND((SUM(s.amount)-SUM(s.qty*p.cost_price))/SUM(s.amount)*100,2) AS 毛利率,
       COUNT(DISTINCT s.txn_id)                 AS 被購買次數
FROM fact_sales s JOIN dim_product p ON s.product_id=p.product_id
GROUP BY p.category ORDER BY 營收 DESC;

-- ---------- Q4 會員 vs 非會員行為 ----------
SELECT IF(s.is_member=1,'會員','非會員') AS 客群,
       COUNT(DISTINCT s.txn_id)                AS 交易筆數,
       SUM(s.amount)                            AS 營收,
       ROUND(SUM(s.amount)/COUNT(DISTINCT s.txn_id),2) AS 客單價,
       ROUND(AVG(s.discount_rate)*100,2)        AS 平均折扣率_pct,
       ROUND(SUM(s.qty)/COUNT(DISTINCT s.txn_id),2)   AS 每單件數
FROM fact_sales s GROUP BY s.is_member;

-- ---------- Q5 支付方式偏好 ----------
SELECT pay_method, COUNT(*) AS 行數, COUNT(DISTINCT txn_id) AS 筆數,
       SUM(amount) AS 營收, ROUND(AVG(amount),2) AS 平均金額
FROM fact_sales GROUP BY pay_method ORDER BY 營收 DESC;

-- ---------- Q6 每小時客流與營收（營業尖峰） ----------
SELECT HOUR(txn_time) AS 時段,
       COUNT(DISTINCT txn_id) AS 交易筆數,
       SUM(amount) AS 營收,
       ROUND(SUM(amount)/COUNT(DISTINCT txn_id),2) AS 客單價
FROM fact_sales GROUP BY HOUR(txn_time) ORDER BY 時段;

-- ---------- Q7 週末 vs 平日 ----------
SELECT IF(d.is_weekend=1,'週末','平日') AS 日期型態,
       COUNT(DISTINCT s.txn_id) AS 交易筆數,
       ROUND(SUM(s.amount)/COUNT(DISTINCT s.txn_date),2) AS 日均營收
FROM fact_sales s JOIN dim_date d ON s.txn_date=d.date_key
GROUP BY d.is_weekend;

-- ---------- Q8 熱銷商品 TOP15 ----------
SELECT p.product_name, p.category, st.store_name,
       SUM(s.qty) AS 銷量, SUM(s.amount) AS 營收,
       ROUND(SUM(s.amount)-SUM(s.qty*p.cost_price),2) AS 毛利
FROM fact_sales s
JOIN dim_product p ON s.product_id=p.product_id
JOIN dim_store   st ON s.store_id=st.store_id
GROUP BY p.product_id, p.product_name, p.category, st.store_id, st.store_name
ORDER BY 營收 DESC LIMIT 15;

-- ---------- Q9 低庫存預警：庫存 < 安全庫存 ----------
SELECT st.store_name, p.product_name, p.category,
       i.on_hand, i.safety_stock,
       i.safety_stock - i.on_hand        AS 缺口,
       ROUND(i.cost_total,2)             AS 庫存成本,
       p.supplier
FROM snap_inventory i
JOIN dim_product p ON i.product_id=p.product_id
JOIN dim_store   st ON i.store_id=st.store_id
WHERE i.on_hand < i.safety_stock
ORDER BY 缺口 DESC;

-- ---------- Q10 生鮮報損風險：臨期品（生鮮保質期≤7天，已過 N 天） ----------
SELECT st.store_name, p.product_name,
       i.on_hand, i.cost_total,
       p.prod_date, p.shelf_life_day,
       DATEDIFF('2026-09-28', p.prod_date) AS 已存放天數,
       p.shelf_life_day - DATEDIFF('2026-09-28', p.prod_date) AS 剩餘天數
FROM snap_inventory i
JOIN dim_product p ON i.product_id=p.product_id
JOIN dim_store   st ON i.store_id=st.store_id
WHERE p.is_fresh=1
  AND p.shelf_life_day - DATEDIFF('2026-09-28', p.prod_date) <= 2
  AND i.on_hand > 0
ORDER BY 剩餘天數 ASC;

-- ---------- Q11 費用結構 + 單店淨利 ----------
SELECT st.store_name,
       SUM(CASE WHEN e.category='租金' THEN e.amount ELSE 0 END)     AS 租金,
       SUM(CASE WHEN e.category='員工工資' THEN e.amount ELSE 0 END) AS 工資,
       SUM(CASE WHEN e.category='水電費' THEN e.amount ELSE 0 END)   AS 水電,
       SUM(CASE WHEN e.category='損耗報損' THEN e.amount ELSE 0 END) AS 報損,
       SUM(CASE WHEN e.category='物流配送' THEN e.amount ELSE 0 END) AS 物流,
       SUM(CASE WHEN e.category='設備維護' THEN e.amount ELSE 0 END) AS 維護,
       SUM(CASE WHEN e.category='促銷物料' THEN e.amount ELSE 0 END) AS 促銷,
       SUM(CASE WHEN e.category='衛生耗材' THEN e.amount ELSE 0 END) AS 耗材,
       SUM(e.amount)                                                AS 費用合計,
       (SELECT SUM(s2.amount)
          FROM fact_sales s2 JOIN dim_product p2 ON s2.product_id=p2.product_id
         WHERE s2.store_id=st.store_id)
        - SUM(e.amount)                                             AS 營收減費用
FROM fact_expense e JOIN dim_store st ON e.store_id=st.store_id
GROUP BY st.store_id, st.store_name ORDER BY 費用合計 DESC;

-- ---------- Q12 每日營收走勢（給 Power BI 折線圖） ----------
SELECT s.txn_date, d.is_weekend,
       SUM(s.amount)                 AS 日營收,
       COUNT(DISTINCT s.txn_id)     AS 日交易數,
       ROUND(SUM(s.amount)/COUNT(DISTINCT s.txn_id),2) AS 日客單價
FROM fact_sales s JOIN dim_date d ON s.txn_date=d.date_key
GROUP BY s.txn_date, d.is_weekend ORDER BY s.txn_date;
