This is just a placeholder to push file structure to repo.

Please follow this tutorial page: https://docs.snowplow.io/docs/modeling-your-data/modeling-your-data-with-dbt/dbt-quickstart/media-player/ to configure and run snowplow media package locally.

Reminder:
dissable the failing tests, by adding the following code to you `dbt_project.yml` file once it has been generated

tests:
  snowplow_media_player:
    base:
      scratch:
        dbt_utils_expression_is_true_snowplow_media_player_base_events_this_run_duration_secs___0:
          enabled: false

Please follow these docs: https://docs.snowplow.io/docs/modeling-your-data/running-data-models-via-snowplow-bdp/dbt/ to schedule the model in Snowplow BDP console.