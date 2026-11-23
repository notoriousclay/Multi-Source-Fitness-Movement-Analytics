{{ config(materialized='view') }}

WITH shoe_usage AS (
    SELECT
        COALESCE(shoe_name, 'Unknown / Default') AS shoe_name,
        MIN(activity_date) AS first_used_date,
        MAX(activity_date) AS last_used_date,
        COUNT(strava_id) AS total_runs,
        ROUND(SUM(distance_km), 2) AS total_distance_km,
        ROUND(SUM(duration_min), 2) AS total_duration_min,
        ROUND(AVG(pace_decimal_min), 2) AS avg_pace_decimal_min
    FROM {{ ref('stg_strava__activities') }}
    WHERE activity_type = 'Run'
    GROUP BY shoe_name
),

shoe_depreciation AS (
    SELECT
        shoe_name,
        first_used_date,
        last_used_date,
        total_runs,
        total_distance_km,
        total_duration_min,
        avg_pace_decimal_min,
        600.0 AS lifespan_threshold_km,
        ROUND(GREATEST(0.0, 600.0 - total_distance_km), 2) AS remaining_distance_km,
        ROUND(LEAST(100.0, (total_distance_km / 600.0) * 100.0), 1) AS wear_pct,
        CASE
            WHEN (total_distance_km / 600.0) >= 1.0 THEN 'Retired / Overdue'
            WHEN (total_distance_km / 600.0) >= 0.8 THEN 'High Mileage / Replace Soon'
            WHEN (total_distance_km / 600.0) >= 0.5 THEN 'Mid Life'
            ELSE 'Fresh / Healthy'
        END AS shoe_status
    FROM shoe_usage
)

SELECT * FROM shoe_depreciation
