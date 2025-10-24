# Segment to Snowplow Migration dbt Package

A reusable dbt package for migrating historical Segment event data to Snowplow's `atomic.events` schema format, with support for custom context generation and event classification.

## Overview

This package transforms raw Segment event data stored in your data warehouse into Snowplow-compatible format, including:

- **Column Mapping**: Maps Segment column names to Snowplow `atomic.events` schema
- **Event Classification**: Reclassifies Segment events into Snowplow event types (page_view, page_ping, unstruct)
- **Context Generation**: Creates Snowplow contexts from Segment properties
- **Custom Contexts**: Supports both OOTB and custom context schemas
- **Source Filtering**: Process all or specific Segment sources

## Features

- ✅ Handles multiple Segment sources/schemas automatically
- ✅ Flexible column mapping with fallback support (multiple possible source columns)
- ✅ Event renaming via configurable mappings (exact match or pattern-based)
- ✅ Static and conditional custom context application
- ✅ Snowplow OOTB mobile contexts (mobile_context, mobile_application)
- ✅ App ID mapping by source
- ✅ Development mode with row limits for testing

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Segment Source Tables                     │
│  (Multiple schemas with varied column names/structures)     │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              base_column_mapping.sql (Base Layer)            │
│  • Unions all Segment sources                                │
│  • Standardizes column names → Snowplow schema               │
│  • Creates context data objects (JSON)                       │
│  • Adds source_relation tracking                             │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│          final_column_mapping.sql (Assembly Layer)           │
│  • Applies event classification/renaming                     │
│  • Wraps contexts in Snowplow schema format                  │
│  • Applies static & conditional custom contexts              │
│  • Sets app_id by source                                     │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              Snowplow-Compatible Output Table                │
│         (Ready for Snowplow processing/querying)             │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

- **dbt**: Version 1.0.0 or higher
- **Data Warehouse**: Snowflake (can be adapted for other warehouses)
- **Segment Data**: Historical Segment events loaded into your warehouse
- **Python**: 3.8+ (for dbt-snowflake)

## Installation

### 1. Clone or Add as Package

**Option A: Use as standalone project**
```bash
git clone https://github.com/patrickbald/segment-snowplow-dbt-migration.git
cd segment-snowplow-dbt-migration
```

**Option B: Add as dbt package** (future - once published)
```yaml
# packages.yml
packages:
  - git: https://github.com/patrickbald/segment-snowplow-dbt-migration.git
    revision: main
```

### 2. Set Up Python Environment

```bash
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

### 3. Configure dbt Profile

Create or update `~/.dbt/profiles.yml`:

```yaml
snowplow_segment_migration:
  target: dev
  outputs:
    dev:
      type: snowflake
      account: YOUR_ACCOUNT
      user: YOUR_USERNAME
      password: YOUR_PASSWORD
      role: YOUR_ROLE
      database: YOUR_DATABASE
      warehouse: YOUR_WAREHOUSE
      schema: YOUR_SCHEMA
      threads: 4
    
    prod:
      type: snowflake
      account: YOUR_ACCOUNT
      user: YOUR_USERNAME
      # ... production settings
```

### 4. Test Connection

```bash
dbt debug
```

## Configuration

### Required Setup

#### 1. Update Source Configuration

Edit `models/sources/segment_sources.yml` to match your Segment data structure:

```yaml
sources:
  - name: your_segment_source
    database: YOUR_SEGMENT_DATABASE  # e.g., REDSHIFT_BACKUP
    schema: YOUR_SEGMENT_SCHEMA      # e.g., PRODUCTION_WEBSITE
    tables:
      - name: PAGE_VIEWS
      - name: BUTTON_CLICKS
      # ... your tables
```

#### 2. Create Mapping Tables

Create three mapping tables in your warehouse to control event classification and context application:

**a) Event Rename Mapping**
```sql
CREATE TABLE YOUR_MAPPINGS_SCHEMA.event_rename_mapping (
    snowplow_event VARCHAR,
    source_pattern VARCHAR,
    pattern_type VARCHAR,  -- 'EXACT' or 'LIKE'
    priority INTEGER,
    is_active BOOLEAN
);

-- Example data:
INSERT INTO YOUR_MAPPINGS_SCHEMA.event_rename_mapping VALUES
    ('page_view', 'production_website.pages', 'EXACT', 1, TRUE),
    ('page_view', 'mobile_app.screens', 'EXACT', 1, TRUE),
    ('page_ping', '%page_ping%', 'LIKE', 2, TRUE);
```

**b) Static Context Mappings**
```sql
CREATE TABLE YOUR_MAPPINGS_SCHEMA.custom_context_static_mappings (
    table_schema VARCHAR,
    table_name VARCHAR,
    context_type VARCHAR,    -- e.g., 'ui_element', 'email_list'
    context_data VARIANT,    -- JSON object
    is_active BOOLEAN
);

-- Example data:
INSERT INTO YOUR_MAPPINGS_SCHEMA.custom_context_static_mappings VALUES
    ('production_website', 'button_click', 'ui_element', 
     PARSE_JSON('[{"name": "cta-button", "action": "click"}]'), TRUE);
```

**c) Conditional Context Mappings**
```sql
CREATE TABLE YOUR_MAPPINGS_SCHEMA.custom_context_conditional_mappings (
    table_schema VARCHAR,
    table_name VARCHAR,
    context_type VARCHAR,
    condition_field VARCHAR,
    condition_operator VARCHAR,  -- e.g., '=', 'IS NULL', 'LIKE'
    condition_value VARCHAR,
    context_data VARIANT,
    is_active BOOLEAN
);

-- Example data:
INSERT INTO YOUR_MAPPINGS_SCHEMA.custom_context_conditional_mappings VALUES
    ('production_website', 'email_submit', 'email_list', 
     'mailing_list', '=', 'newsletter', 
     PARSE_JSON('[{"id": 1, "name": "Newsletter"}]'), TRUE);
```

#### 3. Configure dbt_project.yml

Update `dbt_project.yml` with your configuration:

```yaml
vars:
  # Source filtering
  include_sources:
    - your_segment_source_1
    - your_segment_source_2
    # Or leave empty to process all sources
  
  # Database and schema for mapping tables
  mappings_database: YOUR_DATABASE
  mappings_schema: YOUR_MAPPINGS_SCHEMA
  
  # Snowplow OOTB context schemas
  snowplow_context_schemas:
    mobile_context: 'iglu:com.snowplowanalytics.snowplow/mobile_context/jsonschema/1-0-3'
    mobile_application: 'iglu:com.snowplowanalytics.mobile/application/jsonschema/1-0-0'
  
  # Custom context schemas (update with your schemas)
  custom_context_schemas:
    ui_element: 'iglu:com.yourcompany/ui_element/jsonschema/1-0-0'
    email_list: 'iglu:com.yourcompany/email_list/jsonschema/1-0-0'
  
  # App ID mapping by source
  app_id_mapping:
    your_website: 'web-app'
    your_ios_app: 'ios-app'
    your_android_app: 'android-app'
  
  # Column rename mappings (Segment → Snowplow)
  column_rename_map:
    event_id: 'id'
    user_id: ['user_id', 'userid']
    collector_tstamp: 'received_at'
    derived_tstamp: 'timestamp'
    # ... see dbt_project.yml for full list
  
  # OOTB context definitions (which Segment columns map to context fields)
  snowplow_context_definitions:
    mobile_context:
      osVersion: 'context_os_version'
      osType: 'context_os_name'
      deviceManufacturer: 'context_device_manufacturer'
  
  # Custom context definitions (column-based)
  custom_context_definitions:
    resource:
      resource_id: 'resource_id'
      resource_title: ['title', 'page_title']
```

## Usage

### Development Mode

Test with a limited dataset first:

```bash
# Runs with LIMIT 10000 on dev target
dbt run --target dev
```

### Production Mode

Run the full migration:

```bash
dbt run --target prod
```

### Run Specific Models

```bash
# Just the base layer
dbt run --select base_column_mapping

# Just the final output
dbt run --select final_column_mapping
```

## Configuration Reference

### Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `include_sources` | No | List of source names to process. Empty = all sources |
| `exclude_sources` | No | List of source names to exclude |
| `mappings_database` | Yes | Database containing mapping tables |
| `mappings_schema` | Yes | Schema containing mapping tables |
| `use_explicit_columns` | No | Default true. False = include all columns from sources |
| `app_id_mapping` | Yes | Maps source names to app_id values |
| `column_rename_map` | Yes | Maps Snowplow columns to Segment column name(s) |
| `snowplow_context_schemas` | No | Schema URLs for OOTB Snowplow contexts |
| `custom_context_schemas` | Yes | Schema URLs for your custom contexts |
| `snowplow_context_definitions` | No | Field mappings for OOTB contexts |
| `custom_context_definitions` | No | Field mappings for custom contexts (column-based) |

### Column Rename Map Format

The `column_rename_map` supports multiple possible source columns with automatic coalescing:

```yaml
column_rename_map:
  # Single source column
  event_id: 'id'
  
  # Multiple possible columns (will COALESCE)
  user_id: ['user_id', 'userid', 'user_testing']
  
  # Handles typos/variants automatically
  dvce_screenwidth: ['context_screen_width', 'screen_width']
```

### Context Definition Format

**Column-based contexts** (built from Segment columns):

```yaml
custom_context_definitions:
  resource:
    resource_id: 'resource_id'
    resource_title: ['book_name', 'title', 'page_title']
```

**Event-based contexts** (via mapping tables):
- Static: Always applied to specific source tables
- Conditional: Applied based on field values

## Output Schema

The final output table includes:

- All standard Snowplow `atomic.events` columns
- Context arrays in Snowplow self-describing JSON format
- `source_relation` for tracking original Segment table
- `original_event_name` for audit trail

Example output structure:
```json
{
  "event_id": "uuid",
  "event": "unstruct",
  "event_name": "button_click",
  "original_event_name": "production_website.cta_click",
  "contexts_com_yourcompany_ui_element_1": [
    {
      "schema": "iglu:com.yourcompany/ui_element/jsonschema/1-0-0",
      "data": {
        "name": "cta-button",
        "action": "click"
      }
    }
  ]
}
```

## Testing & Validation

See `dev_testing_plan.md` for comprehensive testing queries including:

- Event classification accuracy
- Context data integrity
- Schema URL validation
- Row count validation
- Performance monitoring

Example validation query:
```sql
SELECT 
    source_relation,
    original_event_name,
    event,
    COUNT(*) as event_count
FROM final_column_mapping
GROUP BY 1, 2, 3
ORDER BY 4 DESC;
```

## Incremental Scaling

The package is designed for incremental scaling:

1. **Start small**: Test with 1-2 sources
2. **Add sources**: Incrementally add more `include_sources`
3. **Increase limits**: Gradually increase dev row limits
4. **Full production**: Remove limits and process all data

## Troubleshooting

### Row Count Discrepancies

If you see unexpected row multiplication:
- Check for multiple matching event mappings (use priority field)
- Verify conditional context logic isn't creating cartesian products
- Use `QUALIFY` clauses to ensure one row per event_id

### Missing Contexts

If contexts aren't appearing:
- Verify schema URLs match exactly
- Check mapping table `is_active` flags
- Confirm source column names match `column_rename_map`

### Performance Issues

For large datasets:
- Materialize models as tables (not views)
- Use warehouse-appropriate clustering keys
- Consider incremental models for ongoing migration

## Customization Examples

### Adding a New Custom Context

1. **Define the schema URL**:
```yaml
custom_context_schemas:
  product: 'iglu:com.yourcompany/product/jsonschema/1-0-0'
```

2. **Add field mappings** (if column-based):
```yaml
custom_context_definitions:
  product:
    product_id: 'product_id'
    product_name: ['product_name', 'item_name']
    product_price: 'price'
```

3. **Or add to mapping tables** (if event-based):
```sql
INSERT INTO custom_context_static_mappings VALUES
    ('ecommerce', 'product_view', 'product', 
     PARSE_JSON('...'), TRUE);
```

### Filtering Specific Time Ranges

Add to base model:
```sql
WHERE derived_tstamp >= '2024-01-01'
  AND derived_tstamp < '2025-01-01'
```

## Contributing

Contributions welcome! Areas for improvement:

- Support for additional data warehouses (BigQuery, Redshift)
- Incremental model patterns
- Additional OOTB context support
- Performance optimizations
- Testing framework

## License

[Specify your license]

## Support

For issues or questions:
- GitHub Issues: [repo URL]
- Documentation: [docs URL]

## Acknowledgments

Built for migrating from Segment to Snowplow analytics while preserving historical event data and custom context information.