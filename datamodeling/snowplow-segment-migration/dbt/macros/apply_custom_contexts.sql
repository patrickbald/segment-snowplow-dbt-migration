-- macros/apply_custom_contexts.sql

{% macro apply_custom_contexts() %}
    {%- set custom_context_mappings = var('custom_context_mappings', {}) -%}
    {%- set custom_context_schemas = var('custom_context_schemas', {}) -%}
    
    {#- Generate each custom context column -#}
    {%- for context_name, schema_url in custom_context_schemas.items() -%}
    {%- set has_matches = false -%}
    {%- for event_key, context_map in custom_context_mappings.items() -%}
        {%- if context_name ~ '_context' in context_map.keys() -%}
            {%- set has_matches = true -%}
            {%- break -%}
        {%- endif -%}
    {%- endfor -%}
    
    ,ARRAY_CONSTRUCT_COMPACT(
        {%- if has_matches -%}
        CASE 
            {%- for event_key, context_map in custom_context_mappings.items() -%}
                {%- for context_type, context_data in context_map.items() -%}
                    {%- if context_type == context_name ~ '_context' -%}
            WHEN LOWER(SOURCE_RELATION) = LOWER('{{ event_key }}')
            THEN OBJECT_CONSTRUCT(
                'schema', '{{ schema_url }}',
                'data', PARSE_JSON('{{ context_data | tojson }}')
            )
                    {%- endif -%}
                {%- endfor -%}
            {%- endfor -%}
            ELSE NULL
        END
        {%- else -%}
        NULL
        {%- endif -%}
    ) AS {{ ('contexts_com_desiringgod_' ~ context_name ~ '_1') | upper }}
    {%- endfor -%}

{% endmacro %}