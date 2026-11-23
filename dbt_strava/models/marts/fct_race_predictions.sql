{{
    config(
        materialized='table'
    )
}}

WITH baseline_candidate AS (
    SELECT
        strava_id,
        activity_date,
        activity_name,
        distance_km,
        duration_min,
        pace_decimal_min,
        pace_formatted,
        ROUND(duration_min * POWER(5.0 / distance_km, 1.06), 2) AS normalized_5k_min
    FROM {{ ref('stg_strava__activities') }}
    WHERE activity_type = 'Run'
      AND distance_km >= 3.0
      AND activity_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 60 DAY)
    QUALIFY ROW_NUMBER() OVER (ORDER BY normalized_5k_min ASC) = 1
),

race_targets AS (
    SELECT '5K' AS race_name, 5.0 AS target_distance_km, 1 AS sort_order UNION ALL
    SELECT '10K', 10.0, 2 UNION ALL
    SELECT 'Half Marathon', 21.0975, 3 UNION ALL
    SELECT 'Marathon', 42.195, 4
),

predictions AS (
    SELECT
        t.sort_order,
        t.race_name,
        t.target_distance_km,
        b.strava_id AS baseline_activity_id,
        b.activity_name AS baseline_workout_name,
        b.activity_date AS baseline_workout_date,
        b.distance_km AS baseline_distance_km,
        b.pace_formatted AS baseline_pace,
        ROUND(b.duration_min * POWER(t.target_distance_km / b.distance_km, 1.06), 2) AS projected_time_min,
        ROUND((b.duration_min * POWER(t.target_distance_km / b.distance_km, 1.06)) / t.target_distance_km, 2) AS projected_pace_dec_min
    FROM race_targets t
    CROSS JOIN baseline_candidate b
)

SELECT
    sort_order,
    race_name,
    target_distance_km,
    baseline_activity_id,
    baseline_workout_name,
    baseline_workout_date,
    baseline_distance_km,
    baseline_pace,
    projected_time_min,
    projected_pace_dec_min,
    CONCAT(
        LPAD(CAST(FLOOR(projected_time_min / 60) AS STRING), 2, '0'), ':',
        LPAD(CAST(MOD(CAST(FLOOR(projected_time_min) AS INT64), 60) AS STRING), 2, '0'), ':',
        LPAD(CAST(MOD(CAST(ROUND(projected_time_min * 60) AS INT64), 60) AS STRING), 2, '0')
    ) AS projected_time_formatted,
    CONCAT(
        LPAD(CAST(FLOOR(projected_pace_dec_min) AS STRING), 2, '0'), ':',
        LPAD(CAST(MOD(CAST(ROUND(projected_pace_dec_min * 60) AS INT64), 60) AS STRING), 2, '0'), '/km'
    ) AS projected_pace_formatted,
    ROUND(60.0 / projected_pace_dec_min, 2) AS projected_speed_kmh
FROM predictions
