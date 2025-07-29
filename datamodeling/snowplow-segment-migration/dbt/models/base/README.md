# Model: Base_column_mappings.sql

## Purpose:
Find all raw event tables from the `REDSHIFT_BACKUP` database and stack them into a single table with consistent schema

## How it works:
1. Uses Jinja loop to automatically find every source table under `REDSHIFT_BACKUP`
2. Performs a `union_relation` to stack all tables and standardize shared columns into the corresponding snowplow column
3. Adds source relation column to every row denoting original segment table

## Model Output:
- Single snowflake table with one row for every event in the segment source tables
- Standardized column names for those that map to snowplow atomic event cols
