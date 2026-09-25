# Olist Analytics Warehouse

> **End-to-end Data Engineering & Analytics Project**
>
> Raw Brazilian e-commerce data → ETL → MySQL Data Warehouse → Data
> Quality → Analytics → Performance Tuning → Streamlit Dashboard

------------------------------------------------------------------------

## 1. Project Overview

This project builds an end-to-end analytics warehouse for the **Olist
Brazilian E-Commerce Public Dataset**.

The pipeline takes raw CSV files through data preparation, staging,
dimensional modeling, transformation, validation, business analysis,
performance tuning, reporting tables, Python statistical analysis, and a
Streamlit dashboard.

### Architecture

``` text
Olist CSV Dataset
       │
       ▼
scripts/prep_csvs.py
       │
       ▼
Clean CSV files
       │
       ▼
MySQL staging layer
       │
       ▼
Star-schema warehouse
       │
       ├── Data quality checks
       ├── Retention analysis
       ├── Delivery analysis
       ├── Revenue & seller analysis
       └── Performance tuning
       │
       ▼
Reporting / summary tables
       │
       ├── Python statistical analysis
       │
       ▼
docs/figures/
       │
       ▼
Streamlit Dashboard
```

------------------------------------------------------------------------

# 2. Technology Stack

-   **Python 3.11+**
-   **MySQL 8.0+**
-   **Pandas**
-   **SQLAlchemy**
-   **PyMySQL**
-   **SciPy**
-   **Matplotlib**
-   **Streamlit**
-   **PowerShell / Windows**

------------------------------------------------------------------------

# 3. Repository Structure

``` text
olist-analytics-warehouse/
│
├── dashboard/
│   └── app.py
│
├── docs/
│   ├── findings.md
│   ├── performance.md
│   └── figures/
│
├── scripts/
│   ├── analysis.py
│   ├── make_fake_olist.py
│   └── prep_csvs.py
│
├── sql/
│   ├── 01_create_staging.sql
│   ├── 02_load_data.sql
│   ├── 03_create_warehouse.sql
│   ├── 04_transform.sql
│   ├── 05_data_quality.sql
│   ├── 06_analysis_retention.sql
│   ├── 07_analysis_delivery.sql
│   ├── 08_analysis_revenue_sellers.sql
│   ├── 09_performance_tuning.sql
│   └── 10_summary_tables.sql
│
├── data/
│   ├── raw/
│   └── clean/
│
├── .gitignore
└── README.md
```

------------------------------------------------------------------------

# 4. Clone the Repository

Open PowerShell and move to your project directory:

``` powershell
cd "E:\NIT ROURKELA\PROJECTS"
```

Clone the repository:

``` powershell
git clone https://github.com/Kolpi03/olist-analytics-warehouse.git
```

Move into the project:

``` powershell
cd .\olist-analytics-warehouse
```

Verify:

``` powershell
git status
```

------------------------------------------------------------------------

# 5. Obtain the Olist Dataset

Download the **Olist Brazilian E-Commerce Public Dataset** and extract
the archive.

For this setup, the downloaded archive was extracted under:

``` text
E:\NIT ROURKELA\PROJECTS\archive
```

The dataset should contain these nine CSV files:

``` text
olist_customers_dataset.csv
olist_geolocation_dataset.csv
olist_order_items_dataset.csv
olist_order_payments_dataset.csv
olist_order_reviews_dataset.csv
olist_orders_dataset.csv
olist_products_dataset.csv
olist_sellers_dataset.csv
product_category_name_translation.csv
```

------------------------------------------------------------------------

# 6. Create the Raw Data Directory

From the project root:

``` powershell
New-Item -ItemType Directory -Force .\data\raw
```

Copy the nine CSV files into:

``` text
E:\NIT ROURKELA\PROJECTS\olist-analytics-warehouse\data\raw
```

You can verify:

``` powershell
Get-ChildItem .\data\raw
```

------------------------------------------------------------------------

# 7. Create a Python Virtual Environment

From the project root:

``` powershell
python -m venv .venv
```

Activate it:

``` powershell
.\.venv\Scripts\Activate.ps1
```

Your prompt should now begin with:

``` text
(.venv)
```

------------------------------------------------------------------------

# 8. Install Python Dependencies

Install the required packages:

``` powershell
pip install pandas sqlalchemy pymysql matplotlib scipy streamlit
```

Verify:

``` powershell
python --version
pip list
```

------------------------------------------------------------------------

# 9. Prepare the Raw CSV Files

Run:

``` powershell
python scripts\prep_csvs.py --raw data/raw --out data/clean
```

The preparation step should process approximately:

  Dataset                  Expected rows
  ---------------------- ---------------
  customers                       99,441
  geolocation                  1,000,163
  order_items                    112,650
  payments                       103,886
  reviews                         99,224
  orders                          99,441
  products                        32,951
  sellers                          3,095
  category translation                71

The command creates:

``` text
data/clean/
```

------------------------------------------------------------------------

# 10. Install / Verify MySQL

The tested environment used **MySQL Server 8.4.x**.

Check:

``` powershell
mysql --version
```

Expected form:

``` text
mysql  Ver 8.4.x ...
```

If `mysql` is not recognized, add the MySQL binary directory to the
current PowerShell session:

``` powershell
$env:Path += ";C:\Program Files\MySQL\MySQL Server 8.4\bin"
```

Then:

``` powershell
mysql --version
```

------------------------------------------------------------------------

# 11. Start / Initialize MySQL

If MySQL has not already been initialized, create the data directory:

``` powershell
New-Item -ItemType Directory -Force "C:\ProgramData\MySQL\MySQL Server 8.4\Data"
```

From the MySQL installation directory, initialize the database:

``` powershell
cd "C:\Program Files\MySQL\MySQL Server 8.4"
```

``` powershell
.\bin\mysqld.exe --initialize-insecure --basedir="C:\Program Files\MySQL\MySQL Server 8.4" --datadir="C:\ProgramData\MySQL\MySQL Server 8.4\Data"
```

Start MySQL if it is not already running.

Verify the server:

``` powershell
mysql -u root -p -e "SELECT VERSION();"
```

------------------------------------------------------------------------

# 12. Enable LOCAL INFILE

The project loads cleaned CSVs using MySQL `LOAD DATA LOCAL INFILE`.

Enable it:

``` powershell
mysql -u root -p -e "SET GLOBAL local_infile = 1;"
```

------------------------------------------------------------------------

# 13. Important Windows / PowerShell Note

The SQL commands in many Linux tutorials use:

``` bash
mysql < sql/file.sql
```

**Do not use this syntax in PowerShell.**

PowerShell treats `<` differently.

Use:

``` powershell
Get-Content .\sql\FILE.sql | mysql --local-infile=1 -u root -p
```

for every SQL script.

------------------------------------------------------------------------

# 14. Create the Staging Layer

Run:

``` powershell
Get-Content .\sql\01_create_staging.sql | mysql --local-infile=1 -u root -p
```

Verify:

``` powershell
mysql -u root -p -e "SHOW DATABASES;"
```

You should see:

``` text
olist
```

------------------------------------------------------------------------

# 15. Load the Clean CSV Data

Run:

``` powershell
Get-Content .\sql\02_load_data.sql | mysql --local-infile=1 -u root -p
```

Verify staging tables:

``` powershell
mysql -u root -p -e "USE olist; SHOW TABLES;"
```

You should see the staging tables, including:

``` text
stg_customers
stg_orders
stg_order_items
stg_order_payments
stg_order_reviews
stg_products
stg_sellers
stg_geolocation
stg_category_translation
```

------------------------------------------------------------------------

# 16. Create the Data Warehouse

Run:

``` powershell
Get-Content .\sql\03_create_warehouse.sql | mysql --local-infile=1 -u root -p
```

The warehouse includes dimensions and facts such as:

``` text
dim_customer
dim_date
dim_geography
dim_product
dim_seller

fact_orders
fact_order_items
fact_payments

map_customer_id
data_quality_checks
```

------------------------------------------------------------------------

# 17. Transform the Warehouse

Run:

``` powershell
Get-Content .\sql\04_transform.sql | mysql --local-infile=1 -u root -p
```

Verify key row counts:

``` powershell
mysql -u root -p -e "USE olist; SELECT COUNT(*) AS customers FROM dim_customer; SELECT COUNT(*) AS orders FROM fact_orders; SELECT COUNT(*) AS order_items FROM fact_order_items; SELECT COUNT(*) AS payments FROM fact_payments;"
```

Expected results from the completed run:

``` text
dim_customer      96,096
fact_orders       99,441
fact_order_items  112,650
fact_payments     103,886
```

------------------------------------------------------------------------

# 18. Run Data Quality Checks

Run:

``` powershell
Get-Content .\sql\05_data_quality.sql | mysql --local-infile=1 -u root -p
```

All checks should have:

``` text
status = PASS
```

The completed execution passed the project's validation checks,
including:

-   expected order counts
-   expected item counts
-   customer-grain validation
-   orphan order items
-   orphan reviews
-   unresolved products
-   duplicate order IDs
-   review validity
-   payment/order consistency
-   date consistency
-   delivery timestamp consistency

**Do not continue if critical data-quality checks fail.**

------------------------------------------------------------------------

# 19. Run Retention Analysis

``` powershell
Get-Content .\sql\06_analysis_retention.sql | mysql --local-infile=1 -u root -p
```

This produces:

-   repeat-customer analysis
-   cohort retention
-   customer segmentation
-   time between purchases

------------------------------------------------------------------------

# 20. Run Delivery Analysis

``` powershell
Get-Content .\sql\07_analysis_delivery.sql | mysql --local-infile=1 -u root -p
```

This produces:

-   order lifecycle timings
-   delivery status distribution
-   delivery lateness buckets
-   review impact
-   first-order lateness vs repeat purchase
-   state-level delivery performance

------------------------------------------------------------------------

# 21. Run Revenue & Seller Analysis

``` powershell
Get-Content .\sql\08_analysis_revenue_sellers.sql | mysql --local-infile=1 -u root -p
```

This produces:

-   monthly revenue
-   category Pareto analysis
-   seller performance
-   seller escalation flags
-   seller concentration
-   freight-distance analysis
-   payment analysis

------------------------------------------------------------------------

# 22. Run Performance Tuning

``` powershell
Get-Content .\sql\09_performance_tuning.sql | mysql --local-infile=1 -u root -p
```

This script:

-   examines execution plans
-   compares query strategies
-   refreshes optimizer statistics
-   demonstrates index usage
-   evaluates covering indexes
-   compares analytical approaches

------------------------------------------------------------------------

# 23. Create Reporting / Summary Tables

Run:

``` powershell
Get-Content .\sql\10_summary_tables.sql | mysql --local-infile=1 -u root -p
```

This creates the reporting layer used by the dashboard, including:

``` text
rpt_monthly_kpis
rpt_seller_scorecard
rpt_category_performance
```

Verify:

``` powershell
mysql -u root -p -e "USE olist; SHOW TABLES;"
```

------------------------------------------------------------------------

# 24. Run Python Statistical Analysis

Run:

``` powershell
python scripts\analysis.py --password "YOUR_MYSQL_PASSWORD"
```

The script connects directly to MySQL and **does not read the raw
CSVs**.

The script produces:

``` text
docs/figures/lateness_vs_review.png
docs/figures/cohort_retention.png
docs/figures/category_pareto.png
docs/figures/freight_drivers.png
```

The tested execution produced:

``` text
MySQL connection successful.

lateness vs review:
Pearson r = -0.291
Spearman rho = -0.178

pareto:
18/72 categories = 80% of revenue

freight drivers:
r_distance = 0.408
r_weight   = 0.613
```

------------------------------------------------------------------------

# 25. Launch the Streamlit Dashboard

Run:

``` powershell
streamlit run dashboard\app.py
```

Open:

``` text
http://localhost:8501
```

The dashboard provides:

-   headline KPIs
-   monthly revenue
-   delivery reliability
-   category performance
-   seller action monitoring
-   analytical tables
-   project findings

------------------------------------------------------------------------

# 26. Troubleshooting

### `mysql is not recognized`

Add MySQL to the current PowerShell PATH:

``` powershell
$env:Path += ";C:\Program Files\MySQL\MySQL Server 8.4\bin"
```

------------------------------------------------------------------------

### PowerShell `<` error

Don't run:

``` powershell
mysql < sql\01_create_staging.sql
```

Use:

``` powershell
Get-Content .\sql\01_create_staging.sql | mysql --local-infile=1 -u root -p
```

------------------------------------------------------------------------

### Python cannot connect to MySQL

If the password contains special characters such as `@`, the SQLAlchemy
connection URL must be constructed safely.

The project uses:

``` python
from sqlalchemy.engine import URL

url = URL.create(
    drivername="mysql+pymysql",
    username=args.user,
    password=args.password,
    host=args.host,
    port=int(args.port),
    database=args.db,
)

engine = create_engine(url)
```

Do not expose the database password in GitHub.

------------------------------------------------------------------------

### Verify MySQL independently

``` powershell
mysql -u root -p -e "USE olist; SELECT COUNT(*) FROM fact_orders;"
```

Expected:

``` text
99441
```

------------------------------------------------------------------------

### Streamlit dashboard does not load

First verify:

``` powershell
mysql -u root -p -e "USE olist; SHOW TABLES;"
```

Then verify the reporting tables exist:

``` powershell
mysql -u root -p -e "USE olist; SELECT COUNT(*) FROM rpt_monthly_kpis;"
```

------------------------------------------------------------------------

# 27. Re-running the Project

After the initial setup, the usual workflow is:

``` powershell
cd "E:\NIT ROURKELA\PROJECTS\olist-analytics-warehouse"

.\.venv\Scripts\Activate.ps1

python scripts\prep_csvs.py --raw data/raw --out data/clean

Get-Content .\sql\01_create_staging.sql | mysql --local-infile=1 -u root -p
Get-Content .\sql\02_load_data.sql | mysql --local-infile=1 -u root -p
Get-Content .\sql\03_create_warehouse.sql | mysql --local-infile=1 -u root -p
Get-Content .\sql\04_transform.sql | mysql --local-infile=1 -u root -p
Get-Content .\sql\05_data_quality.sql | mysql --local-infile=1 -u root -p
Get-Content .\sql\06_analysis_retention.sql | mysql --local-infile=1 -u root -p
Get-Content .\sql\07_analysis_delivery.sql | mysql --local-infile=1 -u root -p
Get-Content .\sql\08_analysis_revenue_sellers.sql | mysql --local-infile=1 -u root -p
Get-Content .\sql\09_performance_tuning.sql | mysql --local-infile=1 -u root -p
Get-Content .\sql\10_summary_tables.sql | mysql --local-infile=1 -u root -p

python scripts\analysis.py --password "YOUR_MYSQL_PASSWORD"

streamlit run dashboard\app.py
```

------------------------------------------------------------------------

# 28. Important Data Modeling Decision

The project distinguishes between:

-   `customer_id` --- order-level identifier
-   `customer_unique_id` --- person-level identifier

The completed warehouse contains:

``` text
99,441 order-level customer IDs
96,096 unique people
```

The customer dimension uses `customer_unique_id`, while
`map_customer_id` resolves order-level IDs.

This distinction is essential for calculating repeat-customer behavior
correctly.

------------------------------------------------------------------------

# 29. Project Completion Checklist

``` text
[✓] Repository cloned
[✓] Dataset downloaded
[✓] Raw CSVs placed in data/raw
[✓] Python virtual environment created
[✓] Python dependencies installed
[✓] MySQL installed / initialized
[✓] LOCAL INFILE enabled
[✓] Staging layer created
[✓] CSV data loaded
[✓] Warehouse created
[✓] Transformations completed
[✓] Data quality checks passed
[✓] Retention analysis completed
[✓] Delivery analysis completed
[✓] Revenue & seller analysis completed
[✓] Performance tuning completed
[✓] Summary tables created
[✓] Python analysis completed
[✓] Figures generated
[✓] Streamlit dashboard running
```

------------------------------------------------------------------------

# 30. Final Result

The completed system provides a reproducible end-to-end analytics
workflow:

**Raw Data → Warehouse → Validation → Business Analysis → Statistical
Analysis → BI Dashboard**

The project is designed so that the dashboard and Python analysis read
from the warehouse/reporting layer rather than directly from the raw CSV
files.
