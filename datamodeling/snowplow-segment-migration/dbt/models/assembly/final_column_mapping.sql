{#- Get the event mapping dictionaries from the project vars -#}
{%- set source_relation_event_map = var('event_rename_map', {}) -%}
{%- set context_definitions = var('context_definitions', {}) -%}


WITH unioned_events AS (
    SELECT * FROM {{ ref('base_column_mapping') }}
)

SELECT
    -- 1. Select the final, correctly-named Snowplow atomic event columns directly
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
    
    -- 2. Keep the original event name for reference, and create the final event name
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

    -- 3. Dynamically create a separate column for each context
    {% for context_var_name, context_map in context_definitions.items() %}
    {%- set data_column = (context_var_name ~ '_data') | upper -%}
    ,ARRAY_CONSTRUCT_COMPACT(
        IFF(
            {{ data_column }} IS NOT NULL AND {{ data_column }} != PARSE_JSON('{}'),
            OBJECT_CONSTRUCT(
                'schema', '{{ var(context_var_name) }}',
                'data', {{ data_column }}
            ),
            NULL
        )
    ) AS "{{ context_var_name }}"
    {% endfor %}

    -- 4. Pass through any other columns for final analysis or auditing
    ,SOURCE_RELATION

FROM unioned_events