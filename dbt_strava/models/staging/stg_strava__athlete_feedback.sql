{{ config(materialized='view') }}

WITH feedback AS (
    SELECT
        feedback_id,
        strava_id,
        CAST(feedback_timestamp AS TIMESTAMP) AS feedback_timestamp,
        DATE(feedback_timestamp) AS feedback_date,
        input_type,
        raw_content,
        CAST(rpe AS INT64) AS rpe,
        soreness_location,
        fatigue_level,
        coach_followup_notes,
        CAST(ingested_at AS TIMESTAMP) AS ingested_at
    FROM {{ source('strava_raw', 'athlete_feedback') }}
    QUALIFY ROW_NUMBER() OVER (PARTITION BY feedback_id ORDER BY ingested_at DESC) = 1
)

SELECT * FROM feedback
