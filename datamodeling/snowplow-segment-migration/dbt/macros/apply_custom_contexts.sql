{% macro apply_custom_contexts() %}
    {%- set custom_context_definitions = var('custom_context_definitions', {}) -%}
    {%- set custom_context_mappings = var('custom_context_mappings', {}) -%}
    {%- set custom_context_schemas = var('custom_context_schemas', {}) -%}
    
    {#- First, handle column-based custom contexts from definitions -#}
    {%- for context_var_name, context_map in custom_context_definitions.items() -%}
    {%- set data_column = (context_var_name ~ '_data') | upper -%}
    {%- set schema_url = custom_context_schemas.get(context_var_name, '') -%}
    ,ARRAY_CONSTRUCT_COMPACT(
        IFF(
            {{ data_column }} IS NOT NULL AND {{ data_column }} != PARSE_JSON('{}'),
            OBJECT_CONSTRUCT(
                'schema', '{{ schema_url }}',
                'data', {{ data_column }}
            ),
            NULL
        )
    ) AS {{ ('contexts_com_desiringgod_' ~ context_var_name ~ '_1') | upper }}
    {%- endfor -%}
    
    {#- Then handle event-based custom contexts from mappings -#}
    {%- for context_name, schema_url in custom_context_schemas.items() -%}
    {#- IMPORTANT: Skip contexts already handled by definitions -#}
    {%- if context_name not in custom_context_definitions -%}
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
    {%- endif -%}  {#- End of skip check -#}
    {%- endfor -%}

{% endmacro %}