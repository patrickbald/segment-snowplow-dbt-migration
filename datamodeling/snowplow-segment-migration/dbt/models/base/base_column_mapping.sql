-- models/base/base_column_mapping.sql

{%- set column_rename_map = var('column_rename_map', {}) -%}
{%- set context_definitions = var('context_definitions', {}) -%}
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

{%- if var('use_explicit_columns', false) -%}
    {%- set select_mode = 'explicit' -%}
{%- else -%}
    {%- set select_mode = 'all' -%}
{%- endif -%}

{#- Call the macro to perform the union on the filtered list of sources -#}
{{ union_sources_with_renaming(
    relations=all_sources,
    column_map=column_rename_map,
    context_definitions=context_definitions,
    select_mode=select_mode
) }}