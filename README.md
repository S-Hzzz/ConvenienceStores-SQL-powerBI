# ConvenienceStores-SQL-powerBI
Portfolio project for Data Analyst / BI role. Dataset is simulated practice data, NOT real business data.

## Project Overview
1. Data source: Simulated transaction, inventory, purchasing and expense data of 4 convenience stores.
2. MySQL: Build table schema, import CSV raw data, run exploratory SQL queries to discover transaction patterns.
3. Power BI: Build star-schema data model, write custom DAX measures and build interactive dashboard.
4. Business goal: Monitor store sales performance, product category trend, customer consumption behaviour and low stock inventory risk.

## Tech Stack
- MySQL 8.0: DDL table creation, CSV import, exploratory data analysis with SQL
- Power BI Desktop: Star schema modelling, DAX, interactive dashboard
- GitHub: Store dataset, SQL scripts, DAX code and dashboard screenshots

## Repository Structure
├── datasets/                    # Simulated CSV source data
│   ├── purchase.csv
│   ├── inventory.csv
│   ├── sales.csv
│   └── expense.csv
├── sql_scripts/
│   ├── 01_create_tables.sql     # Create database & tables schema
│   ├── 02_import_csv.sql        # Script for loading CSV data
│   └── 03_queries.sql # Business SQL analysis
├── powerbi_project/
│   ├── screenshots/             # Power BI dashboard screenshots
│   └── DAX_measures.txt          # All custom DAX measures
└── docs/
    └── data_dictionary.md        # Field definition for all tables
