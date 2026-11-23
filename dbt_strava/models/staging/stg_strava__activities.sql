{{ config(materialized='view') }}

WITH raw_activities AS (
    SELECT
        CAST(Strava_ID AS INT64) AS strava_id,
        CAST(Date AS DATE) AS activity_date,
        Name AS activity_name,
        Type AS activity_type,
        CAST(Distance_km AS FLOAT64) AS distance_km,
        CAST(Duration_min AS FLOAT64) AS duration_min,
        CAST(Elapsed_Time_min AS FLOAT64) AS elapsed_time_min,
        Pace AS pace_formatted,
        ROUND(SAFE_DIVIDE(Duration_min, NULLIF(Distance_km, 0)), 2) AS pace_decimal_min,
        CAST(Elevation_m AS FLOAT64) AS elevation_gain_m,
        CAST(Calories AS FLOAT64) AS calories,
        CAST(Avg_HR AS FLOAT64) AS avg_heart_rate,
        CAST(Cadence AS FLOAT64) AS cadence,
        CAST(Total_Steps AS INT64) AS activity_steps,
        CAST(Avg_Steps_Min AS FLOAT64) AS avg_steps_per_min,
        CAST(Avg_Strides_Min AS FLOAT64) AS avg_strides_per_min,
        Start_Lat AS start_lat,
        Start_Lng AS start_lng,
        Gear AS shoe_name,
        Start_Time AS start_time_str,
        End_Time AS end_time_str,
        City AS city,
        Country AS country
    FROM {{ source('strava_raw', 'strava_activities') }}
    WHERE Strava_ID IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY Strava_ID ORDER BY Date DESC) = 1
)

SELECT * FROM raw_activities
