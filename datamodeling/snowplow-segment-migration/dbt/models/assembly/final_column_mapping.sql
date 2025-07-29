
-- models/final/final_column_mapping.sql

{%- set columns_to_drop = [
    "EVENT_NAME"
] -%}

WITH unioned_events AS (
    SELECT * FROM {{ ref('base_column_mapping') }}
)

SELECT
    -- Select all columns from the previous step except the original event name
    {{ dbt_utils.star(from=ref('base_column_mapping'), except=columns_to_drop) }},

    -- Keep the original name for reference
    event_name AS original_event_name,

    -- Rename certain events
    CASE
        WHEN event_name LIKE '%_CLICK' THEN 'link_click'
        ELSE 'un-categorized'
    END AS event_name

FROM unioned_events