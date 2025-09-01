{% macro set_app_id() %}
    {%- set app_id_mapping = var('app_id_mapping', {}) -%}
    
    CASE 
        {%- for schema_name, app_id in app_id_mapping.items() %}
        WHEN LOWER(REGEXP_SUBSTR(SOURCE_RELATION, '^[^.]+')) = LOWER('{{ schema_name }}')
        THEN '{{ app_id }}'
        {%- endfor %}
        ELSE COALESCE(APP_ID, 'unknown')
    END AS app_id
    
{% endmacro %}