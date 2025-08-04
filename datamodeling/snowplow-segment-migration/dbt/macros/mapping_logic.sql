-- macros/staging_logic.sql

{% macro stage_source_with_contexts(source_relation, column_map, context_definitions) %}
    
    {%- set source_columns = adapter.get_columns_in_relation(source_relation) -%}
    {%- set source_column_names = source_columns | map(attribute='name') | map('lower') | list -%}
    
    {#- Identify all columns that will be used in a mapping or context -#}
    {%- set handled_cols = [] -%}
    {%- for target_col, source_val in column_map.items() -%}
        {%- if source_val is iterable and source_val is not string -%}
            {%- do handled_cols.extend(source_val) -%}
        {%- else -%}
            {%- do handled_cols.append(source_val) -%}
        {%- endif -%}
    {%- endfor -%}
    
    {%- for context, context_map in context_definitions.items() -%}
        {%- for target, source in context_map.items() -%}
            {%- do handled_cols.append(source) -%}
        {%- endfor -%}
    {%- endfor -%}

    SELECT
        {#- 1. Handle the standard renames and coalesces -#}
        {%- for target_col, source_val in column_map.items() -%}
            {% if source_val is iterable and source_val is not string %}
                {% set existing_cols = [] %}
                {% for col in source_val if col|lower in source_column_names %}
                    {% do existing_cols.append(col) %}
                {% endfor %}

                {% if existing_cols | length > 1 %}
                    {# If more than one column exists, COALESCE them #}
                    COALESCE(
                        {%- for col in existing_cols -%}
                        "{{ col }}"
                        {{- ',' if not loop.last }}
                        {%- endfor -%}
                    )
                {% elif existing_cols | length == 1 %}
                    {# If only one column exists, just select it directly #}
                    "{{ existing_cols[0] }}"
                {% else %}
                    {# If no columns exist, use NULL #}
                    NULL
                {% endif %}

            {% else %}
                {# Simple rename logic - check if the column exists #}
                {% if source_val|lower in source_column_names %}
                    "{{ source_val }}"
                {% else %}
                    NULL
                {% endif %}
            {% endif %}
            AS "{{ target_col }}",
        {%- endfor %}

        {#- 2. Create a JSON object for each defined context -#}
        {%- for context_name, context_map in context_definitions.items() -%}
        OBJECT_CONSTRUCT(
            {%- for target_field, source_field in context_map.items() if source_field|lower in source_column_names -%}
            '{{ target_field }}', "{{ source_field }}"
            {{- ',' if not loop.last }}
            {%- endfor -%}
        ) AS "{{ context_name }}_data",
        {%- endfor %}

        {#- 3. Include all other columns that were not handled -#}
        {%- for col in source_columns if col.name|lower not in handled_cols|lower -%}
            "{{ col.name }}"
            {{- ",\n" if not loop.last }}
        {%- endfor %}

    FROM {{ source_relation }}

    {% if target.name == 'dev' %}
    LIMIT 100
    {% endif %}

{% endmacro %}