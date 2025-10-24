# Snowplow Segment Migration

This dbt project transforms historical raw Segment event data into a format compatible with the Snowplow `atomic.events` schema. It also generates Snowplow-compatible entities and applies a custom entity to identify events that originated from Segment. 

## Project Structure

Models:
- **Sources**: Source definitions for raw Segment data
- **Staging**: Maps applicable Segment fields to Snowplow atomic.events columns
- **Entities**: Builds contexts to capture any remaining data, mobile/web contexts, and attaches from_segment context
- **Core**: Final model which assembles events from staging with created contexts

## Requirements

- dbt-snowflake
- (Recommended) virtual env to run dbt-snowflake
- Applicable profiles.yml file to store connection details

## To run this project:

Set up python virtual env: 
```
    python3 -m venv .venv
    source .venv/bin/activate
```

Install python dependencies: `pip install -r requirements.txt`

Test connection: `dbt debug`

Run Project: `dbt run`