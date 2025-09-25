{%- set snowplow_context_definitions = var('snowplow_context_definitions', {}) -%}
{%- set custom_context_definitions = var('custom_context_definitions', {}) -%}
{%- set snowplow_context_schemas = var('snowplow_context_schemas', {}) -%}
{%- set custom_context_schemas = var('custom_context_schemas', {}) -%}

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

-- Static context mappings
static_contexts AS (
    SELECT 
        LOWER(table_schema || '.' || table_name) as source_pattern,
        context_type,
        context_data
    FROM SEGMENT_MIGRATION_TESTING.MAPPINGS.custom_context_static_mappings
    WHERE is_active = TRUE
),

-- Conditional context mappings
conditional_contexts AS (
    SELECT 
        LOWER(table_schema || '.' || table_name) as source_pattern,
        context_type,
        condition_field,
        condition_operator,
        condition_value,
        context_data
    FROM SEGMENT_MIGRATION_TESTING.MAPPINGS.custom_context_conditional_mappings
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
        EVENT_NAME AS original_event_name,
        COALESCE(
            CASE WHEN rn = 1 THEN mapping_snowplow_event ELSE NULL END,
            EVENT_NAME
        ) AS mapped_event_name
    FROM events_with_mappings
    WHERE rn = 1 OR mapping_snowplow_event IS NULL
),

-- Join with context mappings
events_with_contexts AS (
    SELECT 
        e.*,
        
        -- Static UI Element contexts
        sc_ui.context_data as static_ui_element_data,
        
        -- Static Email List contexts  
        sc_email.context_data as static_email_list_data,
        
        -- Static Resource contexts (for C&C events)
        sc_resource.context_data as static_resource_data,
        
        -- Conditional UI Element contexts
        CASE
            WHEN cc_ui.condition_operator = 'IS NULL' AND e.RESOURCE_SERIES IS NULL THEN cc_ui.context_data
            WHEN cc_ui.condition_field = 'podcast_name' AND e.PODCAST_NAME = cc_ui.condition_value THEN cc_ui.context_data
            WHEN cc_ui.condition_field = 'social_channel_navigated_to' AND e.SOCIAL_CHANNEL_NAVIGATED_TO = cc_ui.condition_value THEN cc_ui.context_data
            WHEN cc_ui.condition_field = 'resource_series' AND e.RESOURCE_SERIES = cc_ui.condition_value THEN cc_ui.context_data
            ELSE NULL
        END as conditional_ui_element_data,
        
        -- Conditional Email List contexts
        CASE
            WHEN cc_email.condition_field = 'mailing_list' AND e.MAILING_LIST = cc_email.condition_value THEN cc_email.context_data
            ELSE NULL
        END as conditional_email_list_data
        
    FROM events_classified e
    
    -- Static context joins
    LEFT JOIN static_contexts sc_ui
        ON LOWER(e.SOURCE_RELATION) = sc_ui.source_pattern
        AND sc_ui.context_type = 'ui_element'
    
    LEFT JOIN static_contexts sc_email
        ON LOWER(e.SOURCE_RELATION) = sc_email.source_pattern
        AND sc_email.context_type = 'email_list'
    
    LEFT JOIN static_contexts sc_resource
        ON LOWER(e.SOURCE_RELATION) = sc_resource.source_pattern
        AND sc_resource.context_type = 'resource'
    
    -- Simplified conditional context joins (CASE statements handle the conditions)
    LEFT JOIN conditional_contexts cc_ui
        ON LOWER(e.SOURCE_RELATION) = cc_ui.source_pattern
        AND cc_ui.context_type = 'ui_element'
    
    LEFT JOIN conditional_contexts cc_email
        ON LOWER(e.SOURCE_RELATION) = cc_email.source_pattern
        AND cc_email.context_type = 'email_list'
)

SELECT
    -- Standard Snowplow columns
    EVENT_ID,
    USER_ID,
    DOMAIN_USERID,
    COLLECTOR_TSTAMP,
    DERIVED_TSTAMP,
    DVCE_CREATED_TSTAMP,
    DVCE_SENT_TSTAMP,
    USER_IPADDRESS,
    USERAGENT,
    PAGE_URL,
    PAGE_TITLE,
    PAGE_REFERRER,
    PAGE_URLPATH,
    OS_TIMEZONE,
    BR_LANG,
    BR_COOKIES,
    DVCE_SCREENWIDTH,
    DVCE_SCREENHEIGHT,
    EVENT_VENDOR,
    NAME_TRACKER,
    V_TRACKER,
    MKT_CONTENT,
    MKT_MEDIUM,
    MKT_NAME,
    MKT_TERM,
    MKT_SOURCE,
    MKT_CAMPAIGN,
    
    -- Set the app_id
    {{ set_app_id() }},
    
    -- Event classification
    original_event_name,
    mapped_event_name AS EVENT_NAME,
    CASE 
        WHEN mapped_event_name = 'page_view' THEN 'page_view'
        WHEN mapped_event_name = 'page_ping' THEN 'page_ping'
        ELSE 'unstruct'
    END AS EVENT

    -- Snowplow OOTB contexts (from column data)
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

    -- Custom UI Element context (merge static and conditional)
    ,ARRAY_CONSTRUCT_COMPACT(
        IFF(
            COALESCE(static_ui_element_data, conditional_ui_element_data) IS NOT NULL,
            OBJECT_CONSTRUCT(
                'schema', '{{ custom_context_schemas.ui_element }}',
                'data', COALESCE(conditional_ui_element_data, static_ui_element_data[0])
            ),
            NULL
        )
    ) AS CONTEXTS_COM_DESIRINGGOD_UI_ELEMENT_1
    
    -- Custom Email List context (merge static and conditional)
    ,ARRAY_CONSTRUCT_COMPACT(
        IFF(
            COALESCE(static_email_list_data, conditional_email_list_data) IS NOT NULL,
            OBJECT_CONSTRUCT(
                'schema', '{{ custom_context_schemas.email_list }}',
                'data', COALESCE(conditional_email_list_data, static_email_list_data[0])
            ),
            NULL
        )
    ) AS CONTEXTS_COM_DESIRINGGOD_EMAIL_LIST_1
    
    -- Custom Resource context (static override or column-based)
    ,ARRAY_CONSTRUCT_COMPACT(
        IFF(
            -- First check for static override (C&C events)
            static_resource_data IS NOT NULL,
            OBJECT_CONSTRUCT(
                'schema', '{{ custom_context_schemas.resource }}',
                'data', static_resource_data[0]
            ),
            -- Otherwise use column-based resource context
            IFF(
                RESOURCE_DATA IS NOT NULL 
                AND RESOURCE_DATA != PARSE_JSON('{}')
                AND RESOURCE_DATA:resource_id IS NOT NULL,
                OBJECT_CONSTRUCT(
                    'schema', '{{ custom_context_schemas.resource }}',
                    'data', OBJECT_INSERT(
                        RESOURCE_DATA,
                        'resource_title',
                        TRIM(REPLACE(COALESCE(RESOURCE_DATA:resource_title::STRING, ''), '| Desiring God', '')),
                        TRUE
                    )
                ),
                NULL
            )
        )
    ) AS CONTEXTS_COM_DESIRINGGOD_RESOURCE_1
    
    ,SOURCE_RELATION

FROM events_with_contexts