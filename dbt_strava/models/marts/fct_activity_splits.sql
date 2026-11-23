{{
    config(
        materialized='table',
        partition_by={
            "field": "split_date",
            "data_type": "date",
            "granularity": "day"
        },
        cluster_by=["strava_id", "split_num"]
    )
}}

WITH splits AS (
    SELECT * FROM {{ ref('stg_strava__activity_splits') }}
),

activities AS (
    SELECT
        strava_id,
        activity_name,
        activity_type,
        shoe_name,
        pace_decimal_min AS activity_avg_pace_decimal_min
    FROM {{ ref('stg_strava__activities') }}
)

SELECT
    s.strava_id,
    a.activity_name,
    a.activity_type,
    a.shoe_name,
    s.split_date,
    s.split_num,
    s.distance_km,
    s.duration_sec,
    s.elapsed_time_sec,
    s.duration_min,
    s.pace_formatted,
    s.pace_decimal_min,
    ROUND(s.pace_decimal_min - a.activity_avg_pace_decimal_min, 2) AS split_pace_delta_from_avg,
    s.elevation_diff_m,
    s.avg_heart_rate,
    s.avg_speed_kmh,
    s.avg_grade_adjusted_speed_kmh,
    s.pace_zone
FROM splits s
LEFT JOIN activities a ON s.strava_id = a.strava_id
