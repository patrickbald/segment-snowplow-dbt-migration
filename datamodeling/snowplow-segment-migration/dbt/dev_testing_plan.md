# Segment to Snowplow Migration: Testing & Production Scaling Plan

## Phase 1: Data Quality Validation (Current State)

### Core Functionality Tests

**Test 1: Event Classification Accuracy**
```sql
SELECT 
    source_relation,
    original_event_name,
    event,
    COUNT(*) as event_count
FROM final_column_mapping
GROUP BY 1, 2, 3
HAVING COUNT(*) > 0
ORDER BY source_relation, original_event_name;

-- Expected: All events should be classified into proper types
-- Flag: Any events still showing original names instead of standardized types
```

**Test 2: Custom Context Data Integrity**
```sql
SELECT 
    source_relation,
    original_event_name,
    CASE 
        WHEN contexts_com_desiringgod_ui_element_1 != PARSE_JSON('[]') THEN 'Has UI Context'
        ELSE 'No UI Context' 
    END as ui_status,
    CASE 
        WHEN contexts_com_desiringgod_email_list_1 != PARSE_JSON('[]') THEN 'Has Email Context'
        ELSE 'No Email Context' 
    END as email_status
FROM final_column_mapping
WHERE source_relation LIKE 'production_desiring_god_website%'
ORDER BY source_relation;

-- Expected: Events should have contexts matching your mapping document
-- Flag: Missing contexts for mapped events, unexpected contexts for unmapped events
```

**Test 3: Schema URL Validation**
```sql
SELECT DISTINCT
    contexts_com_desiringgod_ui_element_1[0]:schema::string as ui_schema,
    contexts_com_desiringgod_email_list_1[0]:schema::string as email_schema
FROM final_column_mapping
WHERE contexts_com_desiringgod_ui_element_1 != PARSE_JSON('[]') 
   OR contexts_com_desiringgod_email_list_1 != PARSE_JSON('[]');

-- Expected: Only your defined schema URLs
-- ui_schema = 'iglu:com.desiringgod/ui_element/jsonschema/1-0-0'
-- email_schema = 'iglu:com.desiringgod/email_list/jsonschema/1-0-0'
```

**Test 4: Data Completeness Check**
```sql
SELECT 
    COUNT(*) as total_rows,
    COUNT(event_id) as has_event_id,
    COUNT(source_relation) as has_source_relation,
    COUNT(CASE WHEN event != original_event_name THEN 1 END) as reclassified_events,
    COUNT(CASE WHEN contexts_com_desiringgod_ui_element_1 != PARSE_JSON('[]') THEN 1 END) as ui_context_events,
    COUNT(CASE WHEN contexts_com_desiringgod_email_list_1 != PARSE_JSON('[]') THEN 1 END) as email_context_events
FROM final_column_mapping;

-- Expected: No NULL event_ids or source_relations
-- Reasonable percentages of reclassified and contextualized events
```

### Context-Specific Validation

**Test 5: UI Element Context Structure Validation**
```sql
SELECT 
    source_relation,
    contexts_com_desiringgod_ui_element_1[0]:data[0]:action::string as action,
    contexts_com_desiringgod_ui_element_1[0]:data[0]:name::string as name,
    contexts_com_desiringgod_ui_element_1[0]:data as full_data
FROM final_column_mapping
WHERE contexts_com_desiringgod_ui_element_1 != PARSE_JSON('[]')
ORDER BY source_relation
LIMIT 10;

-- Expected: Valid action/name values matching your mapping
-- Flag: NULL values, unexpected data structures
```

**Test 6: Email List Context Structure Validation**
```sql
SELECT 
    source_relation,
    contexts_com_desiringgod_email_list_1[0]:data[0]:id::int as list_id,
    contexts_com_desiringgod_email_list_1[0]:data[0]:name::string as list_name,
    contexts_com_desiringgod_email_list_1[0]:data as full_data
FROM final_column_mapping
WHERE contexts_com_desiringgod_email_list_1 != PARSE_JSON('[]')
ORDER BY source_relation
LIMIT 10;

-- Expected: Valid ID numbers and list names from your mapping
-- Flag: NULL values, incorrect IDs/names
```

## Phase 2: Incremental Source Scaling

### Current Configuration Assessment
Your current dbt_project.yml includes only:
```yaml
include_sources:
  - ask_pastor_john          # ~9 tables
  - production_desiring_god_website  # ~100 tables
```

### Scaling Strategy

**Step 1: Add Mobile Sources (Low Risk)**
```yaml
include_sources:
  - ask_pastor_john
  - production_desiring_god_website
  - ask_pastor_john_ios      # Add iOS version
  - solid_joys_android       # Add mobile apps
  - solid_joys_ios
  - sermon_of_the_day_android
  - sermon_of_the_day_ios
```

**Validation Query for Mobile Sources:**
```sql
-- Test mobile context population
SELECT 
    source_relation,
    COUNT(*) as row_count,
    COUNT(CASE WHEN contexts_com_snowplowanalytics_mobile_context_1 != PARSE_JSON('[]') THEN 1 END) as mobile_contexts,
    COUNT(CASE WHEN contexts_com_snowplowanalytics_mobile_application_1 != PARSE_JSON('[]') THEN 1 END) as app_contexts
FROM final_column_mapping
WHERE source_relation LIKE '%ios%' OR source_relation LIKE '%android%'
GROUP BY 1
ORDER BY 1;
```

**Step 2: Add Hub Source (Medium Risk)**
```yaml
include_sources:
  - ask_pastor_john
  - production_desiring_god_website
  - ask_pastor_john_ios
  - solid_joys_android
  - solid_joys_ios
  - sermon_of_the_day_android
  - sermon_of_the_day_ios
  - hub                      # Add hub data
```

**Hub-Specific Validation:**
```sql
-- Test subscription/gift event handling
SELECT 
    source_relation,
    event,
    COUNT(*) as count
FROM final_column_mapping
WHERE source_relation LIKE '%hub%'
GROUP BY 1, 2
ORDER BY 1, 3 DESC;
```

**Step 3: Full Production Scale**
```yaml
# Remove include_sources entirely to process all sources
# include_sources: []  # Comment out to include all
```

### Performance Monitoring

**Test 7: Performance Baseline**
```sql
SELECT 
    'Current Scale' as scale_level,
    COUNT(*) as total_rows,
    COUNT(DISTINCT source_relation) as unique_sources,
    CURRENT_TIMESTAMP as measured_at
FROM final_column_mapping;

-- Run after each scaling step to monitor growth
```

## Phase 3: Row Volume Scaling

### Remove Development Limits

Current limitation in mapping_logic.sql:
```sql
{% if target.name == 'dev' %}
LIMIT 100
{% endif %}
```

**Step 1: Increase Dev Limits**
```sql
{% if target.name == 'dev' %}
LIMIT 10000  -- Increase gradually: 1K → 10K → 100K
{% endif %}
```

**Step 2: Remove Limits for Production**
```sql
-- Comment out or remove the entire LIMIT block for production target
```

### Volume Testing Queries

**Test 8: Row Count Validation by Source**
```sql
SELECT 
    REGEXP_SUBSTR(source_relation, '^[^.]+') as source_schema,
    COUNT(*) as row_count,
    MIN(derived_tstamp) as earliest_event,
    MAX(derived_tstamp) as latest_event
FROM final_column_mapping
GROUP BY 1
ORDER BY 2 DESC;

-- Expected: Reasonable row counts, no massive outliers
```

**Test 9: Data Quality at Scale**
```sql
SELECT 
    DATE_TRUNC('day', derived_tstamp) as event_date,
    COUNT(*) as daily_events,
    COUNT(DISTINCT source_relation) as unique_sources_per_day,
    COUNT(CASE WHEN event_id IS NULL THEN 1 END) as null_event_ids
FROM final_column_mapping
WHERE derived_tstamp >= CURRENT_DATE - 30
GROUP BY 1
ORDER BY 1 DESC
LIMIT 30;

-- Expected: Consistent daily patterns, minimal NULL event_ids
```

## Phase 4: Production Migration Checklist

### Pre-Migration Validation

- [ ] All test queries pass with expected results
- [ ] Custom context mappings verified against source document
- [ ] Event classification covers all major event types
- [ ] Performance acceptable at full scale
- [ ] Backup of current Segment data created
- [ ] Rollback plan documented

### Migration Process

Update dbt_project.yml for production:
```yaml
# 1. Update target and settings
target: 'prod'
use_explicit_columns: false  # Include all columns if needed

# 2. Update model materialization
models:
  snowplow_segment_migration:
    base:
      +materialized: table    # Change from view for performance
    assembly:
      +materialized: table
```

### Post-Migration Monitoring

**Test 10: Production Health Check**
```sql
SELECT 
    'Production Migration' as status,
    COUNT(*) as total_events,
    COUNT(DISTINCT DATE(derived_tstamp)) as days_of_data,
    MIN(derived_tstamp) as earliest_event,
    MAX(derived_tstamp) as latest_event,
    COUNT(DISTINCT source_relation) as total_sources,
    CURRENT_TIMESTAMP as check_time
FROM final_column_mapping;
```

**Test 11: Context Coverage Report**
```sql
SELECT 
    REGEXP_SUBSTR(source_relation, '^[^.]+') as source,
    COUNT(*) as total_events,
    COUNT(CASE WHEN contexts_com_desiringgod_ui_element_1 != PARSE_JSON('[]') THEN 1 END) as ui_contexts,
    COUNT(CASE WHEN contexts_com_desiringgod_email_list_1 != PARSE_JSON('[]') THEN 1 END) as email_contexts,
    ROUND(100.0 * COUNT(CASE WHEN contexts_com_desiringgod_ui_element_1 != PARSE_JSON('[]') THEN 1 END) / COUNT(*), 2) as ui_context_pct
FROM final_column_mapping
GROUP BY 1
ORDER BY 2 DESC;
```

### Rollback Procedure

If issues arise:

1. **Immediate**: Revert to previous `include_sources` configuration
2. **Quick**: Add row limits back to development values  
3. **Emergency**: Switch models back to view materialization
4. **Full Rollback**: Restore from backup and investigate issues

### Success Metrics

- **Data Completeness**: >99% of expected events processed
- **Context Accuracy**: Custom contexts match mapping document 100%
- **Event Classification**: <1% of events remain unclassified  
- **Performance**: Query response times acceptable for end users
- **Error Rate**: <0.1% of transformation errors

## Notes
