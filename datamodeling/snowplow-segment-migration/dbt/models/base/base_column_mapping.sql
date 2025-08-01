-- models/staging/stg_unioned_events.sql

{#-
  Define Segment -> Snowplow column mappings
  KEY: The desired column name.
  VALUE: A LIST of possible source column names. The macro will create a COALESCE() statement.
-#}
{%- set snowplow_column_map = {
    "domain_userid": "anonymous_id",
    "event_id": "id",
    "page_referrer": "referrer",
    "userid": "user_id",
    "collector_tstamp": "received_at"
} -%}

{% if target.name == 'dev' %}

    {#- In DEV, union only the small, sampled models -#}
    {{ dbt_utils.union_relations(
        relations=[
            ref('ask_pastor_john'),
            ref('prod_dg_website'),
            ref('ruby_prod_dg_website')
        ],
        column_override=snowplow_column_map,
        source_column_name='source_relation'
    ) }}

{% else %}

    {#- Dynamically get list of all source tables for union. -#}
    {%- set sources_to_union = [] -%}
    {%- for src in graph.sources.values() if src.database == 'REDSHIFT_BACKUP' -%}
        {%- do sources_to_union.append( source(src.source_name, src.name) ) -%}
    {%- endfor -%}

    {#- Use union_relations to stack tables and assign column names -#}
    {#- WARNING - union relations does not have a limit built in -#}
    {{ dbt_utils.union_relations(
        relations=sources_to_union,
        column_override=snowplow_column_map,
        include=snowplow_column_map.keys() | list,
        source_column_name='source_relation'
    ) }}

{% endif %}