# Olist Analytics Warehouse --- Results & Performance Report

> **Execution Results from the Completed Pipeline**
>
> This document records the results produced by the current local
> execution of the Olist Analytics Warehouse.

------------------------------------------------------------------------

# 1. Executive Summary

The project successfully processed the Olist Brazilian E-Commerce Public
Dataset through a complete analytics pipeline:

``` text
Raw CSVs
   ↓
Data Preparation
   ↓
MySQL Staging
   ↓
Star Schema
   ↓
Data Quality
   ↓
Retention Analysis
   ↓
Delivery Analysis
   ↓
Revenue & Seller Analysis
   ↓
Performance Tuning
   ↓
Reporting Tables
   ↓
Python Statistical Analysis
   ↓
Streamlit Dashboard
```

The complete execution finished successfully.

------------------------------------------------------------------------

# 2. Dataset Loaded

The cleaned dataset contained:

  Dataset                       Rows
  ---------------------- -----------
  Customers                   99,441
  Geolocation              1,000,163
  Order items                112,650
  Payments                   103,886
  Reviews                     99,224
  Orders                      99,441
  Products                    32,951
  Sellers                      3,095
  Category translation            71

------------------------------------------------------------------------

# 3. Warehouse Validation

The final warehouse row counts were:

  Warehouse object          Rows
  -------------------- ---------
  `dim_customer`          96,096
  `fact_orders`           99,441
  `fact_order_items`     112,650
  `fact_payments`        103,886

The data-quality script produced **PASS for all validation checks**.

Checks included:

-   expected row counts
-   customer grain validation
-   orphan records
-   unresolved products
-   duplicate order IDs
-   review-score validity
-   payment/order consistency
-   date consistency
-   delivery timestamp consistency

------------------------------------------------------------------------

# 4. Customer Retention Results

## Customer grain

The analysis demonstrated why the project uses `customer_unique_id` for
person-level retention:

  Grain                    Customers   Repeaters   Repeat rate
  ---------------------- ----------- ----------- -------------
  `customer_id`               99,441       6,342         6.38%
  `customer_unique_id`        96,096       2,997         3.12%

The person-level figure is the appropriate business measure because
multiple order-level customer IDs can belong to the same person.

------------------------------------------------------------------------

## Repeat Purchase Timing

For repeat customers:

  Metric               Result
  ------------------ --------
  Repeat customers      2,914
  Minimum days              0
  Average days             81
  Median days              28
  Maximum days            608

------------------------------------------------------------------------

## Customer Segmentation

  ------------------------------------------------------------------------------
  Segment       Customers \% of base        Avg Avg orders  Avg spend    Revenue
                                        recency                            share
  ----------- ----------- ---------- ---------- ---------- ---------- ----------
  At Risk          38,224     40.00%   445 days       1.03     164.22     39.89%

  New /            34,974     36.60%   138 days       1.00     164.08     36.46%
  Promising                                                           

  Loyal            17,858     18.69%   264 days       1.04     158.25     17.96%

  Needs             3,250      3.40%   233 days       1.00     152.39      3.15%
  Attention                                                           

  Champions         1,254      1.31%   138 days       2.16     319.62      2.55%
  ------------------------------------------------------------------------------

------------------------------------------------------------------------

# 5. Delivery Performance

## Order lifecycle

Average time between major stages:

  Stage                       Average
  --------------------- -------------
  Purchase → Approved      10.1 hours
  Approved → Carrier       66.8 hours
  Carrier → Customer      223.4 hours

The carrier-to-customer stage is the largest average interval.

------------------------------------------------------------------------

## Order Status Distribution

  Status          Orders        \%
  ------------- -------- ---------
  Delivered       96,478    97.02%
  Shipped          1,107     1.11%
  Canceled           625     0.63%
  Unavailable        609     0.61%
  Invoiced           314     0.32%
  Processing         301     0.30%
  Created              5     0.01%
  Approved             2   \~0.00%

------------------------------------------------------------------------

# 6. Delivery Timing vs Customer Experience

  Delivery bucket     Orders   \% delivered   Avg review    1--2★       5★
  ----------------- -------- -------------- ------------ -------- --------
  10+ days early      56,910         59.39%         4.32    8.96%   64.06%
  4--9 days early     24,650         25.72%         4.27    9.29%   60.68%
  On time              7,888          8.23%         4.12   11.38%   54.50%
  1--3 days late       1,852          1.93%         3.29   32.18%   33.21%
  4--7 days late       1,748          1.82%         2.11   67.56%   14.13%
  8--14 days late      1,447          1.51%         1.67   80.10%    6.91%
  15+ days late        1,335          1.39%         1.73   78.20%    7.19%

The results show a strong deterioration in observed review scores as
delivery lateness increases.

------------------------------------------------------------------------

# 7. First-Order Delivery and Repeat Purchase

  First-order experience     Customers   Repeat rate
  ------------------------ ----------- -------------
  First order on time           85,662         3.13%
  First order late               7,592         2.56%

Difference:

``` text
3.13% - 2.56% = 0.57 percentage points
```

The analysis estimated:

``` text
Estimated recoverable revenue: R$6,234.54
```

This is a model-generated estimate and should be presented as an
estimate rather than observed lost revenue.

------------------------------------------------------------------------

# 8. Statistical Analysis

The Python analysis produced:

``` text
Pearson correlation:  -0.291
Spearman correlation: -0.178
```

for delivery delay versus review score.

Interpretation:

> Greater delivery delay is associated with lower review scores in the
> analyzed data.

Correlation does not by itself establish causation.

------------------------------------------------------------------------

# 9. Revenue Performance

The monthly analysis shows the main operating period reaching
approximately:

``` text
November 2017 revenue: R$1.172M
```

Revenue remained around the R\$1M+ range through much of 2018.

The first and final dataset months contain very few observations and
should not be interpreted as representative full months.

------------------------------------------------------------------------

# 10. Category Revenue Concentration

The Pareto analysis found:

``` text
18 of 72 categories generate 80% of revenue
```

Top categories:

    Rank Category                          Revenue   Share
  ------ ----------------------- ----------------- -------
       1 health_beauty             R\$1,258,681.34   9.26%
       2 watches_gifts             R\$1,205,005.68   8.87%
       3 bed_bath_table            R\$1,036,988.68   7.63%
       4 sports_leisure              R\$988,048.97   7.27%
       5 computers_accessories       R\$911,954.32   6.71%

------------------------------------------------------------------------

# 11. Seller Performance

The seller analysis identified:

``` text
103 sellers
out of 2,970 active sellers
= 3.5%
```

These sellers account for approximately **half of late deliveries**
according to the analysis.

The summary-table action classification produced:

  Action       Sellers
  ---------- ---------
  OK             3,034
  WATCH             51
  ESCALATE          10

The dashboard allows these sellers to be filtered by action flag.

------------------------------------------------------------------------

# 12. Seller Escalation Example

The highest-risk seller rows include sellers with late-delivery rates
above 20%.

Example results include:

  State     Orders     Revenue   Late %   Avg review   Avg delivery days
  ------- -------- ----------- -------- ------------ -------------------
  SP            46    2,518.37   34.04%         3.62               18.04
  PR            78   10,961.30   32.10%         2.94               26.23
  SP            44    6,899.57   31.58%         3.07               25.03
  SP            44    5,130.00   31.25%         3.30               18.04
  MG            52    2,843.00   29.41%         3.00               26.78

Seller flags should be interpreted together with order volume; the
dashboard uses a minimum-order threshold before scoring sellers.

------------------------------------------------------------------------

# 13. Freight Analysis

Shipping distance bands produced:

  Distance         Shipments    Avg km   Avg freight   Freight as % of price
  -------------- ----------- --------- ------------- -----------------------
  Under 100 km        21,013      39.9         11.76                  24.54%
  100--300 km         15,571     200.5         16.42                  26.63%
  300--700 km         42,534     458.9         19.83                  32.28%
  700--1500 km        22,923     965.9         23.30                  35.88%
  1500+ km            10,053   2,111.9         35.76                  46.82%

Python correlation analysis:

``` text
Freight vs distance: r = 0.408
Freight vs weight:   r = 0.613
```

Within this analysis, product weight has the stronger Pearson
correlation with freight value.

------------------------------------------------------------------------

# 14. Payment Mix

  -----------------------------------------------------------------------
  Payment           Payments            Avg    Avg payment   Share of GMV
  type                         installments                
  ----------- -------------- -------------- -------------- --------------
  Credit card         76,795           3.51         163.32         78.34%

  Boleto              19,784           1.00         145.03         17.92%

  Voucher              5,775           1.00          65.70          2.37%

  Debit card           1,529           1.00         142.57          1.36%
  -----------------------------------------------------------------------

------------------------------------------------------------------------

# 15. Performance Tuning

The performance script compared query execution plans before and after
indexing.

Examples from the completed execution:

``` text
Seller aggregation:
~973 ms → ~721 ms
```

This represents approximately a **26% reduction** for the measured
seller query.

The execution plans show MySQL using covering indexes such as:

``` text
ix_fo_status_purchase_cover
ix_foi_seller_cover
ix_fo_customer
```

Optimizer statistics were successfully refreshed for:

``` text
fact_orders
fact_order_items
dim_seller
dim_customer
```

------------------------------------------------------------------------

# 16. Index Storage Trade-off

Measured table/index sizes:

  Table                    Data      Index   Index overhead
  ------------------ ---------- ---------- ----------------
  fact_orders          23.55 MB   43.22 MB           183.5%
  fact_order_items     11.52 MB   27.64 MB           240.0%
  fact_payments         9.52 MB   12.06 MB           126.8%

The indexes improve analytical query access but consume additional
storage.

------------------------------------------------------------------------

# 17. Python Figure Outputs

The Python analysis generated four figures:

``` text
docs/figures/
├── lateness_vs_review.png
├── cohort_retention.png
├── category_pareto.png
└── freight_drivers.png
```

### `lateness_vs_review.png`

Shows the decline in mean review score as delivery lateness increases.

### `cohort_retention.png`

Shows retention by acquisition cohort and months since first order.

### `category_pareto.png`

Shows revenue concentration across product categories.

### `freight_drivers.png`

Compares freight value against shipping distance and product weight.

------------------------------------------------------------------------

# 18. Streamlit Dashboard

The dashboard successfully ran locally at:

``` text
http://localhost:8501
```

The dashboard currently provides:

### Overview

-   Revenue
-   Orders
-   Late deliveries
-   Average review
-   Monthly revenue
-   Delivery reliability

### Categories

-   Category revenue
-   Revenue share
-   Orders
-   Average review
-   Late percentage

### Sellers

-   Seller ID
-   State
-   Orders
-   Revenue
-   Late percentage
-   Average review
-   Average delivery days
-   Action flag
-   ESCALATE / WATCH / OK filtering

------------------------------------------------------------------------

# 19. Current Dashboard KPI Snapshot

The executed dashboard displayed:

``` text
Revenue       R$15,737,668
Orders        98,816
Late          10.5%
Avg review    3.87 / 5
```

These figures correspond to the dashboard's selected/default reporting
scope and should be interpreted according to its period filter.

------------------------------------------------------------------------

# 20. Key Business Findings

### Finding 1 --- Retention is low

The person-level repeat rate is approximately:

``` text
3.12%
```

with 2,997 repeaters among 96,096 unique customers.

### Finding 2 --- Delivery lateness is strongly associated with reviews

The statistical analysis gives:

``` text
Pearson r = -0.291
```

and the plotted relationship shows a sharp decline in reviews after
delivery becomes late.

### Finding 3 --- Late first orders have a lower repeat rate

``` text
On-time first order: 3.13%
Late first order:    2.56%
```

### Finding 4 --- Late deliveries are concentrated among a small seller group

``` text
103 / 2,970 active sellers
≈ 3.5%
```

account for approximately half of late deliveries in the analysis.

### Finding 5 --- Revenue is concentrated

``` text
18 / 72 categories
≈ 80% of revenue
```

### Finding 6 --- Product weight is more strongly correlated with freight than distance

``` text
Weight:   r = 0.613
Distance: r = 0.408
```

for the tested dataset and Pearson correlation analysis.

------------------------------------------------------------------------

# 21. Important Interpretation Notes

The results describe relationships in the Olist dataset.

They should not automatically be interpreted as causal effects.

For example:

``` text
Late delivery
     ↓
Lower review
```

is supported as an observed association.

Likewise:

``` text
Late first order
     ↓
Lower repeat rate
```

is an observed difference between groups.

Other factors may contribute to these outcomes, including product,
seller, geography, order value, and customer characteristics.

------------------------------------------------------------------------

# 22. Execution Status

The complete project execution currently stands at:

``` text
[✓] Data preparation
[✓] MySQL staging
[✓] Warehouse creation
[✓] Warehouse transformation
[✓] Data quality validation
[✓] Retention analysis
[✓] Delivery analysis
[✓] Revenue analysis
[✓] Seller analysis
[✓] Performance tuning
[✓] Reporting tables
[✓] Python statistical analysis
[✓] Figure generation
[✓] Streamlit dashboard
```

------------------------------------------------------------------------

# 23. Final Project Outcome

The project successfully demonstrates a complete analytics engineering
workflow:

``` text
DATA
  ↓
ENGINEERING
  ↓
WAREHOUSING
  ↓
QUALITY
  ↓
ANALYTICS
  ↓
STATISTICS
  ↓
BUSINESS INSIGHTS
  ↓
VISUALIZATION
```

The result is a reproducible MySQL-based analytics warehouse with
automated SQL analysis, Python-generated analytical figures, and an
interactive Streamlit reporting layer.
