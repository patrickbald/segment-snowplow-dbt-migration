-- macros/apply_custom_contexts.sql

{% macro apply_custom_contexts() %}
    {%- set custom_context_mappings = var('custom_context_mappings', {}) -%}
    {%- set custom_context_schemas = var('custom_context_schemas', {}) -%}
    
    {#- Generate each custom context column -#}
    {%- for context_name, schema_url in custom_context_schemas.items() -%}
    {%- set target_context_type = context_name ~ '_context' -%}
    
    {#- Collect all WHEN clauses for this context -#}
    {%- set when_clauses = [] -%}
    {%- for event_key, context_map in custom_context_mappings.items() -%}
        {%- for context_type, context_data in context_map.items() -%}
            {%- if context_type == target_context_type -%}
                {%- set when_clause = "WHEN LOWER(SOURCE_RELATION) = LOWER('" ~ event_key ~ "') THEN OBJECT_CONSTRUCT('schema', '" ~ schema_url ~ "', 'data', PARSE_JSON('" ~ (context_data | tojson) ~ "'))" -%}
                {%- do when_clauses.append(when_clause) -%}
            {%- endif -%}
        {%- endfor -%}
    {%- endfor -%}
    
    ,ARRAY_CONSTRUCT_COMPACT(
        {%- if when_clauses | length > 0 %}
        CASE 
            {%- for when_clause in when_clauses %}
            {{ when_clause }}
            {%- endfor %}
            ELSE NULL
        END
        {%- else %}
        NULL
        {%- endif %}
    ) AS {{ ('contexts_com_desiringgod_' ~ context_name ~ '_1') | upper }}
    {%- endfor -%}

{% endmacro %}