-- =============================================================
-- 便利店經營分析 · MySQL 8.0 建表與 CSV 匯入腳本
-- 資料庫：conv_store_analytics
-- 編碼：UTF-8（CSV 已轉為 UTF-8；若用原始 GBK 檔請加 CHARACTER SET gbk）
-- 匯入方式：mysql -u <user> -p conv_store_analytics < 01_ddl_and_load.sql
--          或把下面 LOAD DATA 路徑改成你本機的絕對路徑後在 Workbench 裡逐段執行
-- =============================================================

SET NAMES utf8mb4;
CREATE DATABASE IF NOT EXISTS conv_store_analytics
  DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
USE conv_store_analytics;

-- ---------- 維度表：門店 ----------
CREATE TABLE IF NOT EXISTS dim_store (
  store_id        VARCHAR(10) PRIMARY KEY,
  store_name      VARCHAR(30) NOT NULL UNIQUE,
  city            VARCHAR(20) DEFAULT '香港',
  opened_date     DATE,
  created_at      DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT IGNORE INTO dim_store (store_id, store_name) VALUES
('S01','Bear店'), ('S02','Catty店'), ('S03','Rabbit店'), ('S04','Shiba店');

-- ---------- 維度表：商品（來自 purchase.csv，主資料） ----------
CREATE TABLE IF NOT EXISTS dim_product (
  product_id     INT PRIMARY KEY,
  product_name   VARCHAR(60) NOT NULL,
  category       VARCHAR(20) NOT NULL,
  brand          VARCHAR(60),
  spec           VARCHAR(20),
  unit           VARCHAR(10),
  supplier       VARCHAR(30),
  prod_date      DATE,
  shelf_life_day INT,
  cost_price     DECIMAL(10,2) NOT NULL COMMENT '進貨成本(元)',
  retail_price   DECIMAL(10,2) NOT NULL COMMENT '建議零售價(元)',
  is_fresh       TINYINT(1) DEFAULT 0 COMMENT '1=生鮮',
  KEY idx_cat (category),
  KEY idx_supplier (supplier)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------- 維度表：日期 ----------
CREATE TABLE IF NOT EXISTS dim_date (
  date_key       DATE PRIMARY KEY,
  year           SMALLINT,
  month          TINYINT,
  day            TINYINT,
  weekday        TINYINT COMMENT '1=週一',
  weeknum        TINYINT,
  is_weekend     TINYINT(1)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------- 事實表：銷售明細 ----------
CREATE TABLE IF NOT EXISTS fact_sales (
  txn_id         INT NOT NULL COMMENT '流水號',
  txn_date       DATE NOT NULL,
  txn_time       TIME NOT NULL,
  store_id       VARCHAR(10) NOT NULL,
  product_id     INT NOT NULL,
  qty            INT NOT NULL CHECK (qty > 0),
  unit_price     DECIMAL(10,2) NOT NULL,
  discount_rate  DECIMAL(5,2) DEFAULT 0.00 CHECK (discount_rate BETWEEN 0 AND 1),
  amount         DECIMAL(12,2) NOT NULL COMMENT '實收金額 = qty*unit_price*(1-discount_rate)',
  pay_method     VARCHAR(20) NOT NULL,
  cashier        VARCHAR(20),
  is_member      TINYINT(1) DEFAULT 0,
  PRIMARY KEY (txn_id, product_id),
  KEY idx_date (txn_date),
  KEY idx_store (store_id),
  KEY idx_cat_cover (store_id, txn_date, product_id),
  CONSTRAINT fk_sales_store FOREIGN KEY (store_id) REFERENCES dim_store(store_id),
  CONSTRAINT fk_sales_prod  FOREIGN KEY (product_id) REFERENCES dim_product(product_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------- 事實表：費用 ----------
CREATE TABLE IF NOT EXISTS fact_expense (
  expense_id     INT PRIMARY KEY,
  exp_date       DATE NOT NULL,
  store_id       VARCHAR(10) NOT NULL,
  category       VARCHAR(30) NOT NULL COMMENT '水電費/租金/員工工資/損耗報損...',
  amount         DECIMAL(12,2) NOT NULL,
  payee          VARCHAR(30),
  note           VARCHAR(80),
  KEY idx_exp_date (exp_date),
  KEY idx_exp_store (store_id),
  CONSTRAINT fk_exp_store FOREIGN KEY (store_id) REFERENCES dim_store(store_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------- 快照表：庫存盤點（28/9/2026 靜態快照，退化維度攤平） ----------
CREATE TABLE IF NOT EXISTS snap_inventory (
  inv_id         INT PRIMARY KEY,
  store_id       VARCHAR(10) NOT NULL,
  product_id     INT NOT NULL,
  on_hand        INT NOT NULL COMMENT '庫存數量',
  safety_stock   INT NOT NULL COMMENT '安全庫存',
  cost_total     DECIMAL(12,2) NOT NULL COMMENT '庫存成本(元)',
  snap_date      DATE NOT NULL,
  location       VARCHAR(10),
  UNIQUE KEY uq_store_prod (store_id, product_id),
  CONSTRAINT fk_inv_store FOREIGN KEY (store_id) REFERENCES dim_store(store_id),
  CONSTRAINT fk_inv_prod  FOREIGN KEY (product_id) REFERENCES dim_product(product_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================
-- 匯入 CSV  —— 把路徑改成你本機的絕對路徑
-- MySQL 8.0 若報 secure_file_priv，可先把 CSV 放進 SHOW VARIABLES LIKE '%secure%'; 指向的目錄
-- =============================================================
SET GLOBAL local_infile = 1;

LOAD DATA LOCAL INFILE '/絕對路徑/purchase.utf8.csv'
INTO TABLE dim_product
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(product_id,product_name,category,brand,spec,unit,supplier,@pd,@sl,cost_price,retail_price,@fr)
SET prod_date = STR_TO_DATE(@pd,'%d/%m/%Y'),
    shelf_life_day = @sl,
    is_fresh = IF(@fr='是',1,0);

LOAD DATA LOCAL INFILE '/絕對路徑/sales.utf8.csv'
INTO TABLE fact_sales
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(txn_id,@dt,@tm,store_id,@pname,category,qty,unit_price,discount_rate,amount,pay_method,cashier,@mem)
SET txn_date = STR_TO_DATE(@dt,'%d/%m/%Y'),
    txn_time = STR_TO_DATE(@tm,'%H:%i'),
    product_id = (SELECT product_id FROM dim_product p WHERE p.product_name=@pname AND p.category=category LIMIT 1),
    is_member = IF(@mem='是',1,0);

LOAD DATA LOCAL INFILE '/絕對路徑/expense.utf8.csv'
INTO TABLE fact_expense
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(expense_id,@dt,store_id,store_name,category,amount,payee,note)
SET exp_date = STR_TO_DATE(@dt,'%d/%m/%Y');

LOAD DATA LOCAL INFILE '/絕對路徑/inventory.utf8.csv'
INTO TABLE snap_inventory
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(inv_id,store_id,store_name,product_id,@pn,category,on_hand,safety_stock,cost_total,@sd,location)
SET snap_date = STR_TO_DATE(@sd,'%d/%m/%Y');

-- ---------- 補齊日期維度（2026-09-01 ~ 2026-09-30） ----------
INSERT IGNORE INTO dim_date (date_key, year, month, day, weekday, weeknum, is_weekend)
SELECT d, YEAR(d), MONTH(d), DAY(d),
       WEEKDAY(d)+1, WEEK(d,1), IF(WEEKDAY(d)>=5,1,0)
FROM (
  SELECT DATE_ADD('2026-09-01', INTERVAL seq DAY) d
  FROM (SELECT 0 seq UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL
        SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL
        SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10 UNION ALL SELECT 11 UNION ALL
        SELECT 12 UNION ALL SELECT 13 UNION ALL SELECT 14 UNION ALL SELECT 15 UNION ALL
        SELECT 16 UNION ALL SELECT 17 UNION ALL SELECT 18 UNION ALL SELECT 19 UNION ALL
        SELECT 20 UNION ALL SELECT 21 UNION ALL SELECT 22 UNION ALL SELECT 23 UNION ALL
        SELECT 24 UNION ALL SELECT 25 UNION ALL SELECT 26 UNION ALL SELECT 27 UNION ALL
        SELECT 28 UNION ALL SELECT 29) t
) q;

SELECT 'DDL + LOAD 完成' AS status;
SHOW TABLES;
