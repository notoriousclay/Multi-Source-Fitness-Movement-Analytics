{{ config(materialized='view') }}

WITH strava_daily AS (
    SELECT
        activity_date,
        SUM(activity_steps) AS running_steps,
        ROUND(SUM(distance_km), 2) AS running_distance_km,
        ROUND(SUM(calories), 1) AS active_calories,
        COUNT(strava_id) AS total_activities
    FROM {{ ref('stg_strava__activities') }}
    GROUP BY activity_date
),

fit_daily AS (
    SELECT
        step_date,
        total_steps AS fit_total_steps,
        source_device
    FROM {{ ref('stg_google_fit__daily_steps') }}
),

reconciled AS (
    SELECT
        COALESCE(s.activity_date, f.step_date) AS summary_date,
        COALESCE(s.running_steps, 0) AS strava_steps,
        COALESCE(f.fit_total_steps, 0) AS google_fit_steps,
        -- The true daily total steps is Google Fit (which aggregates passive + active)
        -- If Google Fit is 0 or missing for the day, fall back to Strava steps
        GREATEST(COALESCE(f.fit_total_steps, 0), COALESCE(s.running_steps, 0)) AS reconciled_daily_steps,
        -- Passive steps = Google Fit steps minus active running steps
        GREATEST(0, COALESCE(f.fit_total_steps, 0) - COALESCE(s.running_steps, 0)) AS estimated_passive_steps,
        COALESCE(s.running_distance_km, 0.0) AS running_distance_km,
        COALESCE(s.active_calories, 0.0) AS active_calories,
        COALESCE(s.total_activities, 0) AS total_activities
    FROM strava_daily s
    FULL OUTER JOIN fit_daily f ON s.activity_date = f.step_date
)

SELECT * FROM reconciled
WHERE summary_date IS NOT NULL
