-- macros/staging_logic.sql

{% macro union_sources_with_renaming(relations, column_map, context_definitions, select_mode='explicit') %}

    {#-================================================================================================================-#}
    {#-  STEP 1: Build superset of all columns and identify handled columns.                           -#}
    {#-================================================================================================================-#}
    {%- set all_columns = {} -%}
    {%- set handled_source_cols = [] -%}
    {%- set target_cols = column_map.keys() | map('lower') | list -%} 

    {#- Get all the source columns that will be explicitly handled -#}
    {%- for target_col, source_val in column_map.items() -%}
        {%- if source_val is iterable and source_val is not string -%}
            {%- do handled_source_cols.extend(source_val) -%}
        {%- else -%}
            {%- do handled_source_cols.append(source_val) -%}
        {%- endif -%}
    {%- endfor -%}
    {%- for context, context_map in context_definitions.items() -%}
        {%- do handled_source_cols.extend(context_map.values()) -%}
        {%- do target_cols.append(context ~ '_data') -%} 
    {%- endfor -%}

    {#- Get all columns from sources -#}
    {%- for relation in relations -%}
        {%- set cols = adapter.get_columns_in_relation(relation) -%}
        {%- for col in cols -%}
            {%- do all_columns.update({col.name.lower(): col.data_type}) -%}
        {%- endfor -%}
    {%- endfor -%}

    {#-================================================================================================================-#}
    {#-  STEP 2: Loop through each relation again and generate the final SELECT statements.              -#}
    {#-================================================================================================================-#}
    {% for relation in relations %}
    (
        SELECT
            '{{ relation.source_name | lower }}.{{ relation.name | lower }}' as source_relation,

            {#-- Get the columns for the CURRENT relation being processed --#}
            {%- set relation_cols_lower = adapter.get_columns_in_relation(relation) | map(attribute='name') | map('lower') | list -%}

            {#-- Handle the standard renames and coalesces --#}
            {%- for target_col, source_val in column_map.items() -%}
                {% if source_val is iterable and source_val is not string %}
                    {% set existing_cols = [] %}
                    {% for col in source_val if col.lower() in relation_cols_lower %}
                        {% do existing_cols.append(col) %}
                    {% endfor %}

                    {% if existing_cols | length > 1 %}
                        COALESCE( {%- for col in existing_cols -%} "{{ col }}" {{- ',' if not loop.last }} {%- endfor -%} )
                    {% elif existing_cols | length == 1 %}
                        "{{ existing_cols[0] }}"
                    {% else %}
                        NULL
                    {% endif %}
                {% else %}
                    {%- if source_val.lower() in relation_cols_lower -%} "{{ source_val }}" {%- else -%} NULL {%- endif -%}
                {% endif %}
                AS "{{ target_col }}",
            {%- endfor %}

            {#-- Create a JSON object for each defined context --#}
            {%- for context_name, context_map in context_definitions.items() -%}
            OBJECT_CONSTRUCT(
                {%- for target_field, source_field in context_map.items() if source_field.lower() in relation_cols_lower -%}
                '{{ target_field }}', "{{ source_field }}"
                {{- ',' if not loop.last }}
                {%- endfor -%}
            ) AS "{{ context_name }}_data",
            {%- endfor %}

            {#-- Include all other columns from the superset, that have not been handled or would cause a duplicate --#}
            {%- if select_mode == 'all' -%}
            , {%- for col_name, col_type in all_columns.items() if col_name not in handled_source_cols|map('lower')|list and col_name not in target_cols -%}
                {%- if col_name in relation_cols_lower -%}
                "{{ col_name }}"
                {%- else -%}
                NULL AS "{{ col_name }}"
                {%- endif -%}
                {{- ",\n" if not loop.last }}
            {%- endfor %}
            {%- endif %}

        FROM {{ relation }}

        {% if target.name == 'dev' %}
        LIMIT 100
        {% endif %}
    )

    {{ 'UNION ALL' if not loop.last }}
    {% endfor %}

{% endmacro %}