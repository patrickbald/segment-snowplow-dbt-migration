-- models/assembly/final_column_mapping.sql

WITH unioned_events AS (
    SELECT * FROM {{ ref('base_column_mapping') }}
)

SELECT
    -- Select all standard columns that should be at the top level of the atomic event table
    domain_userid,
    event_id,
    user_id,
    collector_tstamp,

    -- Keep the original event name for reference, and create the normalized name
    event AS original_event_name,
    CASE
        WHEN event LIKE '%Click' THEN 'link_click'
        WHEN event LIKE '%Submit' THEN 'form_submission'
        WHEN event = 'Application Opened' THEN 'application_opened'
        WHEN event = 'Application Installed' THEN 'application_installed'
        ELSE 'un_categorized'
    END AS event_name,

    -- Assemble the final contexts JSON array
    ARRAY_CONSTRUCT_COMPACT(
        -- Mobile Context
        OBJECT_CONSTRUCT(
            'schema', '{{ var("mobile_context_schema") }}',
            'data', mobile_context_data
        )
    ) AS contexts,

    -- You can also bring in the source_relation for final auditing
    source_relation

FROM unioned_events