{#- Get the event mapping dictionary from the project vars -#}
{%- set event_map = var('event_rename_map', {}) -%}
{#- Get the context definitions from the project vars -#}
{%- set context_definitions = var('context_definitions', {}) -%}

WITH unioned_events AS (
    SELECT * FROM {{ ref('base_column_mapping') }}
)

SELECT
    -- 1. Select the final, correctly-named Snowplow atomic event columns directly
    event_id
    ,userid
    ,domain_userid
    ,collector_tstamp
    ,derived_tstamp
    ,dvce_created_tstamp
    ,dvce_sent_tstamp
    ,user_ipaddress
    ,useragent
    ,page_url
    ,page_title
    ,page_referrer
    ,page_urlpath
    ,os_timezone
    ,br_lang
    ,br_cookies
    ,dvce_screenwidth
    ,dvce_screenheight
    ,event_vendor
    ,name_tracker
    ,v_tracker
    
    -- 2. Keep the original event name for reference, and create the normalized name
    ,event AS original_event_name
    ,CASE
        {% for snowplow_event, segment_events in event_map.items() %}
        WHEN event IN (
            {%- for event_name in segment_events -%}
            '{{ event_name }}'
            {{- ',' if not loop.last }}
            {%- endfor -%}
        ) THEN '{{ snowplow_event }}'
        {% endfor %}
        ELSE event
    END AS event

    -- 3. Dynamically create a separate column for each context
    {% for context_var_name, context_map in context_definitions.items() %}
    {%- set data_column = context_var_name ~ '_data' -%}
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
    ,source_relation

FROM unioned_events