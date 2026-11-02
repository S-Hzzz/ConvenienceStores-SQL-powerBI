# 便利店經營分析 · Power BI 數據模型與 DAX

## 一、星型模型（Star Schema）

```
                  ┌──────────────┐
                  │  dim_date    │  ← 日期維度（2026-09-01 ~ 09-30）
                  │  date_key(PK)│
                  └──────┬───────┘
                         │ 1 : N
                         ▼
┌──────────────┐   ┌──────────────┐   ┌──────────────┐
│  dim_store   │──▶│ fact_sales   │◀──│ dim_product  │
│  store_id(PK)│ 1:N│  txn_id     │ N:1│ product_id  │
└──────────────┘   │  txn_date   │   └──────────────┘
                  │  store_id    │          │ N:1
                  │  product_id  │          ▼
                  │  amount      │   ┌──────────────┐
                  │  qty         │   │ dim_category │  ← 可由 dim_product.類別 退化，也可單拆
                  └──────┬───────┘   └──────────────┘
                         │
                         │ 同一事实表可复用于「收入」视角
                         ▼
                  ┌──────────────┐        ┌──────────────┐
                  │ fact_expense │◀───────│  dim_store   │
                  │ exp_date ───────────▶│  dim_date    │  （費用另建日期關係，避免雙向歧義）
                  └──────┬───────┘        └──────────────┘
                         │
                         ▼
                  ┌──────────────┐
                  │snap_inventory│  ← 靜態快照（9/28），不與日期表串，僅按 store/product 切片
                  └──────────────┘

關聯（全部單向，篩選方向：維度 → 事實）：
  dim_date[date_key]       → fact_sales[txn_date]       (1:N)
  dim_store[store_id]      → fact_sales[store_id]       (1:N)
  dim_product[product_id]  → fact_sales[product_id]     (1:N)
  dim_date[date_key]       → fact_expense[exp_date]     (1:N)
  dim_store[store_id]      → fact_expense[store_id]     (1:N)
  dim_store[store_id]      → snap_inventory[store_id]   (1:N, 弱關係)
  dim_product[product_id]  → snap_inventory[product_id] (1:N, 弱關係)
```

> 為什麼費用也單獨掛日期表：銷售與費用是兩個不同粒度的事實表，
> Power BI 裡若只共用一張日期表，切換「月份/週」時兩邊會互相干擾；建議用 **Active 關係指向 sales，expense 用 DAX 的 USERELATIONSHIP 或雙日期表（Date_Sales / Date_Expense）**。

## 二、DAX Measures（直接貼進「度量值」區）

```dax
// ===== 基礎營收 =====
總營收 := SUM(fact_sales[amount])

交易筆數 := DISTINCTCOUNT(fact_sales[txn_id])

客單價 := 
DIVIDE([總營收], [交易筆數], 0)

總件數 := SUM(fact_sales[qty])

件均價 := DIVIDE([總營收], [總件數], 0)

// ===== 毛利（成本取自 dim_product[cost_price]）=====
銷貨成本 :=
SUMX (
    fact_sales,
    fact_sales[qty] * RELATED ( dim_product[cost_price] )
)

毛利 := [總營收] - [銷貨成本]

毛利率 := DIVIDE([毛利], [總營收], 0)

// ===== 會員 / 非會員（用 CALCULATE + FILTER，避免對 BIT 欄位直接篩選的歧義）=====
會員營收 :=
CALCULATE ([總營收], fact_sales[is_member] = 1)

非會員營收 :=
CALCULATE ([總營收], fact_sales[is_member] = 0)

會員客單價 :=
DIVIDE (
    [會員營收],
    CALCULATE ([交易筆數], fact_sales[is_member] = 1),
    0
)

// ===== 時間智能（需確認 dim_date[date_key] 已標記為「日期表」）=====
YTD營收 := TOTALYTD ([總營收], dim_date[date_key])

日均營收 := DIVIDE ([總營收], DISTINCTCOUNT ( fact_sales[txn_date] ), 0)

環比營收 := 
VAR Cur = [總營收]
VAR Prev = CALCULATE ([總營收], DATEADD ( dim_date[date_key], -1, DAY ))
RETURN DIVIDE ( Cur - Prev, Prev, 0 )

// ===== 費用與獲利 =====
總費用 := SUM(fact_expense[amount])

費用率 := DIVIDE ([總費用], [總營收], 0)

營收減費用 := [總營收] - [總費用]

// 各類費用（切圖時直接拿 category 當軸，這些做備用）
租金 := CALCULATE ([總費用], fact_expense[category] = "租金")
人工 := CALCULATE ([總費用], fact_expense[category] = "員工工資")
報損 := CALCULATE ([總費用], fact_expense[category] = "損耗報損")

// ===== 庫存風險（snap_inventory 快照）=====
庫存總成本 := SUM(snap_inventory[cost_total])

低庫存品項數 :=
COUNTROWS (
    FILTER (
        snap_inventory,
        snap_inventory[on_hand] < snap_inventory[safety_stock]
    )
)

低庫存缺貨成本 :=
SUMX (
    FILTER ( snap_inventory, snap_inventory[on_hand] < snap_inventory[safety_stock] ),
    snap_inventory[cost_total]
)

低庫存品項數_全部 :=
COUNTROWS (
    FILTER (
        snap_inventory,
        snap_inventory[on_hand] < snap_inventory[safety_stock]
    )
)

庫存周轉天數_估算 :=
DIVIDE (
    SUM ( snap_inventory[cost_total] ),
    [銷貨成本] / 30,
    0
)

COUNTROWS (
    FILTER (
        snap_inventory,
        snap_inventory[on_hand] < snap_inventory[safety_stock]
    )
)

缺貨缺口件數 :=
SUMX (
    FILTER ( snap_inventory, snap_inventory[on_hand] < snap_inventory[safety_stock] ),
    snap_inventory[safety_stock] - snap_inventory[on_hand]
)

// 生鮮陳列天數佔保質期比例（Power BI 裡用計算列輔助，或用以下度量按上下文算）
生鮮陳列佔比 :=
VAR Base = SELECTEDVALUE ( dim_product[prod_date] )
VAR Life = SELECTEDVALUE ( dim_product[shelf_life_day] )
RETURN
    IF (
        SELECTEDVALUE ( dim_product[is_fresh] ) = 1 && NOT ( ISBLANK ( Base ) ),
        DIVIDE ( DATEDIFF ( Base, DATE ( 2026, 9, 28 ), DAY ), Life, 0 ),
        BLANK ()
    )
```

## 三、儀表板頁面規劃（3 頁）

| 頁籤 | 視覺物件 | 鑽取/交互 |
|---|---|---|
| **1. 經營總覽** | KPI 卡：總營收 / 毛利率 / 客單價 / 交易筆數 / 營收減費用；折線：每日營收+筆數雙軸；柱狀：4 店營收對比；環形：品類營收佔比 | 點店 → 下方全聯動 |
| **2. 商品與客群** | 矩陣：品類 × 店 營收/毛利率（條件格式色階）；TOP15 商品氣泡圖（X=銷量,Y=毛利,大小=營收）；會員 vs 非會員卡片；支付方式 100% 堆疊條；每小時熱力柱 | 時段 → 看尖峰品類 |
| **3. 庫存與風險** | 低庫存警報表（缺口排序）；生鮮「陳列天數/保質期」甘特條；費用結構瀑布圖（租金→工資→水電→報損→淨利）；地圖式店鋪卡片 | 生鮮品項紅黃綠規則：佔比≥90%紅、75-90%黃 |

## 四、兩個關鍵數據口徑提醒（做報告時必須講）

1. **purchase.生產日期 實為「到貨/上架日」**：五花肉(保質5天,日期6/1)、炸雞腿(保質1天,日期6/17)若按日曆算均已過期。
   處理方式：盤點基準日 `2026-09-28`，生鮮風險 = `DATEDIFF(上架日, 09-28) / 保質期`。
   若你的真實口徑是「生產日」，則本批生鮮全部報廢——請先與業務方確認。
2. **expense 日期跨度 1/9~29/9、sales 只有 1/9~30/9**，且費用是「事件型」非每日都有。
   算「日均費用」請用 `費用合計 / 營業天數(30)`，不要直接除以有記錄的天數。
