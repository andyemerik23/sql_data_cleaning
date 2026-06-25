# Automated, Non-Destructive Shipment Data Cleaning Pipeline

A comprehensive, production-grade SQL data cleaning pipeline that transforms raw, messy, and inconsistent logistics records into an analysis-ready database table using PostgreSQL.

---

## 📌 Project Overview

In real-world data warehousing, modifying raw data using destructive commands like `UPDATE` or `DELETE` is highly risky. It destroys data lineage, prevents auditability, and makes reprocessing impossible if cleaning rules change.

This portfolio project showcases a modern, non-destructive, self-cleaning data pipeline architecture. By leveraging cascading Common Table Expressions (CTEs), window functions, and native PostgreSQL statistical tools, the entire data cleaning lifecycle is executed in a single-pass, idempotent query.

The raw shipments table remains completely untouched as an immutable **Single Source of Truth**, while a clean downstream table (`shipments_cleaned`) is dynamically generated.

---

## 🗃️ Dataset Source & Schema

The dataset represents a transactional logistics ledger containing shipment records across regional warehouses.

The raw table suffers from common real-world data entry anomalies, including:

- Casing mismatches
- Arbitrary spacing
- Invalid chronological relationships
- Negative values
- Extreme outliers

### Raw Attributes & Diagnostic Anomalies

| Column | Description | Data Issues |
|----------|-------------|-------------|
| shipment_id | Unique shipment identifier | Duplicate records and inconsistent casing |
| origin_warehouse | Sender warehouse | Leading/trailing spaces and mixed casing |
| destination_city | Destination city | Missing values and inconsistent formatting |
| destination_state | Destination state | Mixed-case state codes (`tx`, `il`) |
| carrier | Logistics carrier | Casing inconsistencies |
| ship_date | Shipment date | Missing values |
| delivery_date | Delivery date | Invalid timelines |
| weight_kg | Package weight | Missing, zero, and negative values |
| freight_cost | Shipping cost | Extreme outliers and missing values |
| shipment_status | Shipment status | Inconsistent casing |
| items_count | Item quantity | Zero and negative values |
| damage_reported | Damage flag | Empty strings, `"NULL"`, and inconsistent values |

---

## 🔄 How This Approach Differs From Traditional Tutorials

Most SQL cleaning tutorials follow a destructive workflow:

```text
[Raw Table]
      │
      ▼
UPDATE table
      │
      ▼
DELETE duplicates
      │
      ▼
ALTER TABLE
      │
      ▼
[Mutated Raw Table]
```

### Why the Traditional Approach Fails in Production

#### ❌ Destructive Mutations

Overwriting raw columns removes the ability to recover original values if cleaning logic changes.

#### ❌ Lack of Automation

Running multiple sequential scripts manually is difficult to schedule, test, and maintain.

#### ❌ Static Thresholding

Outliers are often removed using arbitrary limits rather than statistically calculated boundaries.

---

## ✅ Advanced Pipeline Architecture

Instead of modifying the raw dataset, the cleaning process is modeled as a pure transformation layer:

```text
[Immutable Raw Table]
          │
          ▼
[Cascading CTE Pipeline]
          │
          ▼
[shipments_cleaned]
```

### Benefits

- **Data Lineage** → Raw table remains untouched.
- **Auditability** → Suspicious rows are flagged instead of deleted.
- **Automation Ready** → Single executable query.
- **Statistical Cleaning** → Dynamic IQR-based outlier treatment.

---

# 🛠️ Data Cleaning Process

---

## Step 1 — Text Standardization & Whitespace Trimming

Normalize string formatting and remove unnecessary spaces.

```sql
initcap(trim(s.origin_warehouse)) AS origin_warehouse,
COALESCE(initcap(trim(s.destination_city)), 'Unknown') AS destination_city,
upper(trim(s.destination_state)) AS destination_state,
initcap(trim(s.shipment_status)) AS shipment_status,
initcap(trim(s.carrier)) AS carrier
```

### Actions Performed

- Removes leading/trailing spaces
- Standardizes capitalization
- Converts state codes to uppercase
- Replaces missing cities with `"Unknown"`

---

## Step 2 — Null & Empty String Normalization

Convert string-based null representations into actual SQL `NULL` values.

```sql
CASE
    WHEN trim(s.damage_reported) = ''
      OR s.damage_reported = 'NULL'
      OR s.damage_reported IS NULL THEN NULL
    ELSE initcap(trim(s.damage_reported))
END AS damage_reported
```

### Problem Solved

Converts:

```text
''
'NULL'
NULL
```

into a single consistent database `NULL`.

---

## Step 3 — Non-Destructive Deduplication

Duplicate rows are identified using a window function.

```sql
ROW_NUMBER() OVER (
    PARTITION BY
        initcap(trim(s.origin_warehouse)),
        COALESCE(initcap(trim(s.destination_city)), 'Unknown'),
        initcap(trim(s.carrier)),
        s.ship_date,
        s.weight_kg,
        s.freight_cost
    ORDER BY s.shipment_id
) AS row_num
```

### Why This Is Better

Instead of deleting rows:

- Original data remains untouched
- Duplicates are filtered only in final output
- Full audit trail is preserved

---

## Step 4 — Numerical Anomaly Resolution

### Weight Cleaning

```sql
CASE
    WHEN s.weight_kg <= 0 OR s.weight_kg IS NULL
    THEN (
        SELECT ROUND(AVG(weight_kg))
        FROM shipments
        WHERE weight_kg > 0
    )
    ELSE ABS(s.weight_kg)
END AS weight_kg
```

### Item Count Cleaning

```sql
CASE
    WHEN s.items_count < 0 THEN ABS(s.items_count)
    WHEN s.items_count = 0 OR s.items_count IS NULL
    THEN (
        SELECT ROUND(AVG(items_count))
        FROM shipments
        WHERE items_count > 0
    )
    ELSE s.items_count
END AS items_count
```

### Actions Performed

- Converts negative values to positive
- Replaces zero values
- Imputes missing values using dataset averages

---

## Step 5 — Date Validation & Auditing

Instead of removing invalid dates, the pipeline flags them.

```sql
(delivery_date - ship_date) AS transit_days,

CASE
    WHEN delivery_date IS NULL OR ship_date IS NULL
        THEN 'Missing date'
    WHEN delivery_date = ship_date
        THEN 'Same day delivery'
    WHEN (delivery_date - ship_date) <= 0
        THEN 'Invalid'
    ELSE 'Valid'
END AS date_check
```

### Advantages

- Preserves row counts
- Enables business review
- Improves auditability

---

## Step 6 — Dynamic IQR Outlier Treatment

Outliers are detected using the Interquartile Range (IQR).

### Formula

```math
IQR = Q3 - Q1
```

```math
Lower Bound = Q1 - 1.5(IQR)
```

```math
Upper Bound = Q3 + 1.5(IQR)
```

### Statistical Boundary Calculation

```sql
WITH stats AS (
    SELECT
        percentile_cont(0.25)
        WITHIN GROUP (ORDER BY freight_cost) AS q1,

        percentile_cont(0.75)
        WITHIN GROUP (ORDER BY freight_cost) AS q3

    FROM shipments
    WHERE freight_cost > 0
),
bounds AS (
    SELECT
        q1 - (1.5 * (q3 - q1)) AS lower_bound,
        q3 + (1.5 * (q3 - q1)) AS upper_bound
    FROM stats
)
```

### Benefits

- Automatically adapts to data distribution
- Eliminates arbitrary thresholds
- Preserves business realism

---

# 🎛️ Purpose of `masterquery.sql`

The `masterquery.sql` file acts as the orchestration layer for the entire pipeline.

### Features

#### Idempotent Execution

```sql
DROP TABLE IF EXISTS shipments_cleaned;
```

Can be executed repeatedly without errors.

#### Unified Processing

Runs:

- Statistical calculations
- Cleaning transformations
- Deduplication

inside one execution context.

#### Data Protection

Only reads from raw data.

No destructive mutations occur.

#### Scheduling Ready

Compatible with:

- Airflow
- dbt
- Prefect
- Cron Jobs

---

# 📜 Complete Pipeline Script

The full implementation can be found inside:

```text
masterquery.sql
```

This file creates the final cleaned table:

```sql
CREATE TABLE shipments_cleaned AS
...
```

---

# 📊 Results Comparison

## 🔴 Raw Dataset

| Shipment | Issue |
|-----------|--------|
| SHP-1002 | Delivery before ship date |
| SHP-1003 | Duplicate record |
| SHP-1005 | Negative weight |
| SHP-1013 | Missing city |
| SHP-1016 | $15,000 outlier |
| SHP-1017 | Zero cost and weight |

---

## 🟢 Cleaned Dataset

| Shipment | Resolution |
|-----------|------------|
| SHP-1002 | Flagged as Invalid |
| SHP-1003 | Removed via deduplication |
| SHP-1005 | Weight imputed |
| SHP-1013 | City set to Unknown |
| SHP-1016 | Cost capped via IQR |
| SHP-1017 | Values imputed |

---

# 📈 Key Achievements & Business Impact

### Robust Deduplication

Safely isolated duplicate business records without risking loss of original source data.

---

### Data Standardization

Resolved inconsistencies involving:

- Warehouse names
- Carrier names
- State abbreviations
- Text casing
- Extra whitespace

---

### Dynamic Outlier Mitigation

The extreme shipment cost:

```text
$15,000.00
```

was automatically capped to:

```text
$988.75
```

based on calculated statistical boundaries.

---

### Intelligent Imputation

Automatically corrected:

- Negative weights
- Missing weights
- Zero item counts
- Missing freight costs

using dynamically computed dataset averages.

---

### Built-In Data Quality Audits

Records containing business-rule violations were preserved and flagged rather than removed.

Examples include:

- Delivery date before ship date
- Missing shipment dates
- Same-day delivery anomalies

This ensures stakeholders can review and validate suspicious records without losing valuable operational history.

---

## 🚀 Technologies Used

- PostgreSQL
- SQL Window Functions
- Common Table Expressions (CTEs)
- Statistical Analysis (IQR)
- Data Cleaning & Transformation
- Data Quality Auditing
- ETL Design Principles
- Production Data Engineering Practices

---

## 📂 Output

### SQL Pipeline File

[`masterquery.sql`](./masterquery.sql)

### Raw Source Table

[`dirty_shipments.csv`](./dirty_shipments.csv)

### Final Analytical Table

[`clean_shipments.csv`](./clean_shipments.csv)

The resulting dataset is:

- Analysis-ready
- Fully auditable
- Non-destructive
- Repeatable
- Production-oriented
