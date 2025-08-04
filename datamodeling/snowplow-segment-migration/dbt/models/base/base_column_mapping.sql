-- models/base/base_column_mapping.sql

{#-
  Define the standard column mappings.
  KEY: The new, desired column name.
  VALUE: A LIST of potential source columns to coalesce, or a single STRING for a direct rename.
-#}
{%- set column_rename_map = {
    "domain_userid": "anonymous_id",
    "event_id": "id",
    "userid": "user_id",
    "collector_tstamp": "received_at",
    "page_url": ["url", "context_page_url"]
} -%}

{#-
  Define context mappings.
  - Top-level KEY is the name of your context (e.g., web_page_context).
  - Nested KEY is the target field name in the Snowplow context schema.
  - Nested VALUE is the original source column name.
-#}
{%- set context_definitions = {
    "mobile_context": {
        "osVersion": "context_os_version",
        "osType": "context_device_type",
    }
} -%}


{%- set all_sources = [] -%}
{%- for src in graph.sources.values() if src.database == 'REDSHIFT_BACKUP' -%}
    {%- do all_sources.append(source(src.source_name, src.name)) -%}
{%- endfor -%}


{% for source_relation in all_sources %}
    
    (
        SELECT 
            '{{ source_relation.source_name | lower }}.{{ source_relation.name | lower }}' as source_relation,
            *
        FROM (
            {{ stage_source_with_contexts(
                source_relation=source_relation,
                column_map=column_rename_map,
                context_definitions=context_definitions
            ) }}
        )
    )

    {{ 'UNION ALL' if not loop.last }}

{% endfor %}