-- models/base/base_column_mapping.sql

{#-
  Define the standard column mappings.
-#}
{%- set column_rename_map = {
    "domain_userid": "anonymous_id",
    "event_id": "id",
    "userid": "user_id",
    "collector_tstamp": "received_at",
    "br_lang": "context_locale",
    "derived_timestamp": "timestamp",
    "original_timestamp": "dvce_created_tstamp",
    "dvce_screenheight": 'context_screen_height',
    "dvce_screenwidth": "context_screen_width",
    "dvce_sent_tstamp": "sent_at",
    "event_vendor": "context_app_namespace",
    "name_tracker": "context_library_name",
    "os_timezone": "context_timezone",
    "user_ipaddress": "context_ip",
    "useragent": "context_user_agent",
    "v_tracker": "context_library_verison",
    "page_title": ["context_page_title", "title"],
    "page_url": ["context_page_url", "page_url"],
    "page_urlpath": ["context_page_path", "page_path"],
    "page_referrer": ["context_page_referrer", "page_referrer"],
    "br_cookies": ["browser_cookies_enabled", "broweser_cookies_enabled_yn"],
    "page_url": ["page_url", "url", "context_page_url"],
    "event": ["event_text", "event"]
} -%}

{%- set context_definitions = var('context_definitions', {}) -%}

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