-- macros/mapping_logic.sql

{% macro union_sources_with_renaming(relations, column_map, context_definitions, select_mode='all') %}

    {#-================================================================================================================-#}
    {#-  STEP 1: Build the master "superset" of all columns and identify handled columns.                           -#}
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
    
    {#- Handle arrays in context definitions -#}
    {%- for context, context_map in context_definitions.items() -%}
        {%- for field, source in context_map.items() -%}
            {%- if source is iterable and source is not string -%}
                {%- do handled_source_cols.extend(source) -%}
            {%- else -%}
                {%- do handled_source_cols.append(source) -%}
            {%- endif -%}
        {%- endfor -%}
        {%- do target_cols.append(context ~ '_data') -%} 
    {%- endfor -%}

    {#- Loop through every relation to find all possible columns -#}
    {%- for relation in relations -%}
        {%- set cols = adapter.get_columns_in_relation(relation) -%}
        {%- for col in cols -%}
            {%- do all_columns.update({col.name.lower(): col.data_type}) -%}
        {%- endfor -%}
    {%- endfor -%}

    {#-================================================================================================================-#}
    {#-  STEP 2: Loop through each relation again and generate the final, resilient SELECT statements.              -#}
    {#-================================================================================================================-#}
    {% for relation in relations %}
    (
        SELECT
            '{{ relation.schema | lower }}.{{ relation.name | lower }}' as source_relation,
            {#-- Get the columns for the CURRENT relation being processed --#}
            {%- set relation_cols = adapter.get_columns_in_relation(relation) -%}
            {%- set relation_cols_lower = [] -%}
            {%- for col in relation_cols -%}
                {%- do relation_cols_lower.append(col.name.lower()) -%}
            {%- endfor -%}

            {#-- Handle the standard renames and coalesces --#}
            {%- for target_col, source_val in column_map.items() -%}
                {%- if source_val is iterable and source_val is not string -%}
                    {%- set existing_cols = [] -%}
                    {%- for col in source_val if col.lower() in relation_cols_lower -%}
                        {%- do existing_cols.append(col) -%}
                    {%- endfor -%}

                    {%- if existing_cols | length > 1 -%}
                        COALESCE( {%- for col in existing_cols -%} {{ adapter.quote(col) }} {{- ',' if not loop.last }} {%- endfor -%} )
                    {%- elif existing_cols | length == 1 -%}
                        {{ adapter.quote(existing_cols[0]) }}
                    {%- else -%}
                        NULL
                    {%- endif -%}
                {%- else -%}
                    {%- if source_val.lower() in relation_cols_lower -%} {{ adapter.quote(source_val) }} {%- else -%} NULL {%- endif -%}
                {%- endif %}
                AS {{ target_col }},
            {%- endfor %}

            {#-- Create a JSON object for each defined context --#}
            {%- for context_var_name, context_map in context_definitions.items() -%}
            {%- set column_name = context_var_name ~ '_data' -%}
            OBJECT_CONSTRUCT(
                {%- set field_pairs = [] -%}
                {%- for target_field, source_field in context_map.items() -%}
                    {%- if source_field is iterable and source_field is not string -%}
                        {#- Handle multiple possible source columns -#}
                        {%- set existing_cols = [] -%}
                        {%- for col in source_field if col.lower() in relation_cols_lower -%}
                            {%- do existing_cols.append(col) -%}
                        {%- endfor -%}
                        
                        {%- if existing_cols | length > 0 -%}
                            {%- if existing_cols | length > 1 -%}
                                {%- set coalesce_expr = "COALESCE(" ~ existing_cols | map('tojson') | join(', ') ~ ")" -%}
                                {%- do field_pairs.append("'" ~ target_field ~ "', " ~ coalesce_expr) -%}
                            {%- else -%}
                                {%- do field_pairs.append("'" ~ target_field ~ "', " ~ adapter.quote(existing_cols[0])) -%}
                            {%- endif -%}
                        {%- endif -%}
                    {%- else -%}
                        {#- Handle single source column -#}
                        {%- set source_normalized = source_field.lower().strip('"').strip("'") -%}
                        {%- if source_normalized in relation_cols_lower -%}
                            {%- do field_pairs.append("'" ~ target_field ~ "', " ~ adapter.quote(source_field)) -%}
                        {%- endif -%}
                    {%- endif -%}
                {%- endfor -%}
                
                {#- Output the field pairs -#}
                {%- if field_pairs | length > 0 -%}
                    {{ field_pairs | join(', ') }}
                {%- endif -%}
            ) AS {{ column_name }},
            {%- endfor %}

            {#-- Include all other columns from the superset --#}
            {%- if select_mode == 'all' -%}
            {%- for col_name, col_type in all_columns.items() if col_name not in handled_source_cols|map('lower')|list and col_name not in target_cols -%}
                {%- if col_name in relation_cols_lower -%}
                {{ adapter.quote(col_name) }}
                {%- else -%}
                NULL AS {{ col_name }}
                {%- endif -%}
                {{- ",\n" if not loop.last }}
            {%- endfor %}
            {%- endif %}

        FROM {{ relation }}

        {% if target.name == 'dev' %}
        LIMIT 10000
        {% endif %}
    )

    {{ 'UNION ALL' if not loop.last }}
    {% endfor %}

{% endmacro %}