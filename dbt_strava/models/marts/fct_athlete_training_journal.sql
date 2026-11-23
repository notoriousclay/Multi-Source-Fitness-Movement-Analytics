{{
    config(
        materialized='table',
        partition_by={
            "field": "activity_date",
            "data_type": "date",
            "granularity": "day"
        },
        cluster_by=["activity_type", "shoe_name"]
    )
}}

WITH activities AS (
    SELECT * FROM {{ ref('fct_activities') }}
),

feedback AS (
    SELECT
        strava_id,
        feedback_timestamp,
        input_type,
        raw_content AS athlete_notes,
        rpe,
        soreness_location,
        fatigue_level,
        coach_followup_notes
    FROM {{ ref('stg_strava__athlete_feedback') }}
    QUALIFY ROW_NUMBER() OVER (PARTITION BY strava_id ORDER BY feedback_timestamp DESC) = 1
)

SELECT
    a.strava_id,
    a.activity_date,
    a.activity_name,
    a.activity_type,
    a.distance_km,
    a.duration_min,
    a.pace_formatted,
    a.pace_decimal_min,
    a.elevation_gain_m,
    a.calories,
    a.avg_heart_rate,
    a.cadence,
    a.shoe_name,
    a.acute_workload_7d_km,
    a.chronic_workload_28d_km,
    a.acwr_ratio,
    a.acwr_risk_category,
    -- Qualitative Human-in-the-Loop Feedback
    f.feedback_timestamp,
    f.input_type AS feedback_channel,
    f.athlete_notes,
    f.rpe,
    f.soreness_location,
    f.fatigue_level,
    f.coach_followup_notes,
    CASE 
        WHEN f.strava_id IS NOT NULL THEN 'Feedback Logged'
        ELSE 'Pending Feedback'
    END AS debrief_status
FROM activities a
LEFT JOIN feedback f ON a.strava_id = f.strava_id
