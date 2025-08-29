{#- Get the event mapping dictionaries from the project vars -#}
{%- set source_relation_event_map = var('event_rename_map', {}) -%}
{%- set snowplow_context_definitions = var('snowplow_context_definitions', {}) -%}
{%- set custom_context_definitions = var('custom_context_definitions', {}) -%}
{%- set snowplow_context_column_urls = var('snowplow_context_column_urls', {}) -%}

WITH unioned_events AS (
    SELECT * FROM {{ ref('base_column_mapping') }}
)

SELECT
    -- Grab explicit Snowplow cols
    EVENT_ID
    ,USERID
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
    
    -- Reclassify events based on map in dbt project
    ,EVENT AS original_event_name
    ,CASE
        {% for snowplow_event, relation_patterns in source_relation_event_map.items() %}
        WHEN (
            {% for pattern in relation_patterns -%}
            LOWER(SOURCE_RELATION) LIKE LOWER('{{ pattern }}')
            {%- if not loop.last %} OR {% endif -%}
            {% endfor %}
        )
        THEN '{{ snowplow_event }}'
        {% endfor %}
        ELSE EVENT
    END as event

    -- Create Snowplow contexts from Segment data
    {% for context_var_name, context_map in snowplow_context_definitions.items() %}
    {%- set data_column = (context_var_name ~ '_data') | upper -%}
    {%- set schema_url = snowplow_context_column_urls['contexts_com_snowplowanalytics_snowplow_' ~ context_var_name ~ '_1'] or snowplow_context_column_urls['contexts_com_snowplowanalytics_mobile_' ~ context_var_name ~ '_1'] -%}
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

FROM unioned_events