{#- Get the event mapping dictionaries from the project vars -#}
{%- set snowplow_context_definitions = var('snowplow_context_definitions', {}) -%}
{%- set custom_context_definitions = var('custom_context_definitions', {}) -%}
{%- set snowplow_context_schemas = var('snowplow_context_schemas', {}) -%}

WITH unioned_events AS (
    SELECT * FROM {{ ref('base_column_mapping') }}
),

event_mappings AS (
    SELECT 
        snowplow_event,
        source_pattern,
        pattern_type,
        priority
    FROM SEGMENT_MIGRATION_TESTING.MAPPINGS.event_rename_mapping
    WHERE is_active = TRUE
),

events_with_mappings AS (
    SELECT 
        u.*,
        em.snowplow_event AS mapping_snowplow_event,
        em.priority,
        ROW_NUMBER() OVER (
            PARTITION BY u.EVENT_ID 
            ORDER BY em.priority ASC, em.source_pattern
        ) as rn
    FROM unioned_events u
    LEFT JOIN event_mappings em
        ON CASE 
            WHEN em.pattern_type = 'LIKE' THEN 
                LOWER(u.SOURCE_RELATION) LIKE LOWER(em.source_pattern)
            WHEN em.pattern_type = 'EXACT' THEN 
                LOWER(u.SOURCE_RELATION) = LOWER(em.source_pattern)
            ELSE FALSE
        END
),

events_classified AS (
    SELECT
        *,
        -- Reclassify events based on map in table
        EVENT_NAME AS original_event_name,
        COALESCE(
            CASE WHEN rn = 1 THEN mapping_snowplow_event ELSE NULL END,
            EVENT_NAME
        ) AS mapped_event_name
    FROM events_with_mappings
    WHERE rn = 1 OR mapping_snowplow_event IS NULL
)

SELECT
    -- Grab explicit Snowplow cols
    EVENT_ID
    ,USER_ID
    ,DOMAIN_USERID
    ,COLLECTOR_TSTAMP
    ,DERIVED_TSTAMP
    ,DVCE_CREATED_TSTAMP
    ,DVCE_SENT_TSTAMP
    ,USER_IPADDRESS
    ,USERAGENT
    ,PAGE_URL
    ,PAGE_TITLE
    ,PAGE_REFERRER
    ,PAGE_URLPATH
    ,OS_TIMEZONE
    ,BR_LANG
    ,BR_COOKIES
    ,DVCE_SCREENWIDTH
    ,DVCE_SCREENHEIGHT
    ,EVENT_VENDOR
    ,NAME_TRACKER
    ,V_TRACKER
    ,MKT_CONTENT
    ,MKT_MEDIUM
    ,MKT_NAME
    ,MKT_TERM
    ,MKT_SOURCE
    ,MKT_CAMPAIGN

    
    -- Set the app_id based on the source relation mapping
    ,{{ set_app_id() }}
    
    -- Event name columns
    ,original_event_name
    ,mapped_event_name AS EVENT_NAME
    
    -- Add Snowplow event type classification
    ,CASE 
        WHEN mapped_event_name = 'page_view' THEN 'page_view'
        WHEN mapped_event_name = 'page_ping' THEN 'page_ping'
        ELSE 'unstruct'
    END AS EVENT

    -- Create Snowplow contexts from Segment data
    {% for context_var_name, context_map in snowplow_context_definitions.items() %}
    {%- set data_column = (context_var_name ~ '_data') | upper -%}
    {%- set schema_url = snowplow_context_schemas.get(context_var_name, '') -%}
    ,ARRAY_CONSTRUCT_COMPACT(
        IFF(
            {{ data_column }} IS NOT NULL AND {{ data_column }} != PARSE_JSON('{}'),
            OBJECT_CONSTRUCT(
                'schema', '{{ schema_url }}',
                'data', {{ data_column }}
            ),
            NULL
        )
    ) AS {{ ('contexts_com_snowplowanalytics_' ~ context_var_name ~ '_1') | upper }}
    {% endfor %}

    -- Apply custom contexts using the macro
    {{ apply_custom_contexts() }}
    ,SOURCE_RELATION

FROM events_classified