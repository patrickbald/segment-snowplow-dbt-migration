-- models/base/base_column_mapping.sql

{#-
  Define the standard column mappings.
-#}
{%- set column_rename_map = {
    "domain_userid":    "anonymous_id",
    "event_id":         "id",
    "userid":           "user_id",
    "collector_tstamp": "received_at",
    "page_url":         ["page_url", "url", "context_page_url"],
    "event":            ["event_text", "event"]
} -%}

{#-
  Define context mappings.
-#}
{%- set context_definitions = {
    "mobile_context": {
        "osVersion": "context_os_version",
        "osType": "context_os_name",
        "deviceManufacturer": "context_device_manufacturer",
        "deviceModel": "context_device_model"
    }
} -%}

{#- Get the include/exclude lists from the project vars -#}
{%- set include_list = var('include_sources', []) -%}
{%- set exclude_list = var('exclude_sources', []) -%}

{#- Get a list of all source relations and apply the filtering logic -#}
{%- set all_sources = [] -%}
{%- for src in graph.sources.values() if src.database == 'REDSHIFT_BACKUP' -%}

    {%- set source_name = src.source_name | lower -%}

    {#- Logic to decide whether to include the source in the run -#}
    {%- if (include_list | length > 0 and source_name in include_list) or (include_list | length == 0 and source_name not in exclude_list) -%}
        {%- do all_sources.append(source(src.source_name, src.name)) -%}
    {%- endif -%}

{%- endfor -%}

{#- Call the macro to perform the union on the filtered list of sources -#}
{{ union_sources_with_renaming(
    relations=all_sources,
    column_map=column_rename_map,
    context_definitions=context_definitions
) }}