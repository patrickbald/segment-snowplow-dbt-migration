-- models/base/base_column_mapping.sql

{%- set column_rename_map = var('column_rename_map', {}) -%}
{%- set snowplow_context_definitions = var('snowplow_context_definitions', {}) -%}
{%- set custom_context_definitions = var('custom_context_definitions', {}) -%}
{%- set include_list = var('include_sources', []) -%}
{%- set exclude_list = var('exclude_sources', []) -%}

{#- Combine both context definition types -#}
{%- set all_context_definitions = {} -%}
{%- do all_context_definitions.update(snowplow_context_definitions) -%}
{%- do all_context_definitions.update(custom_context_definitions) -%}

{#- Get a list of all source relations and apply the filtering logic -#}
{%- set all_sources = [] -%}
{%- for src in graph.sources.values() if src.database == 'REDSHIFT_BACKUP' -%}

    {%- set source_name = src.source_name | lower -%}

    {#- Logic to decide whether to include the source in the run -#}
    {%- if (include_list | length > 0 and source_name in include_list) or (include_list | length == 0 and source_name not in exclude_list) -%}
        {%- do all_sources.append(source(src.source_name, src.name)) -%}
    {%- endif -%}

{%- endfor -%}

{%- if var('use_explicit_columns', true) -%}
    {%- set select_mode = 'explicit' -%}
{%- else -%}
    {%- set select_mode = 'all' -%}
{%- endif -%}

{#- Call the macro to perform the union on the filtered list of sources -#}
{{ union_sources_with_renaming(
    relations=all_sources,
    column_map=column_rename_map,
    context_definitions=all_context_definitions,
    select_mode=select_mode
) }}