{{ config(materialized='view') }}

WITH raw_splits AS (
    SELECT
        CAST(Strava_ID AS INT64) AS strava_id,
        CAST(Date AS DATE) AS split_date,
        CAST(Split_Num AS INT64) AS split_num,
        CAST(Distance_km AS FLOAT64) AS distance_km,
        CAST(Duration_sec AS INT64) AS duration_sec,
        CAST(Elapsed_Time_sec AS INT64) AS elapsed_time_sec,
        CAST(Duration_min AS FLOAT64) AS duration_min,
        Pace AS pace_formatted,
        CAST(Pace_Dec_Min AS FLOAT64) AS pace_decimal_min,
        CAST(Elevation_Diff_m AS FLOAT64) AS elevation_diff_m,
        CAST(Avg_HR AS FLOAT64) AS avg_heart_rate,
        CAST(Avg_Speed_kmh AS FLOAT64) AS avg_speed_kmh,
        CAST(Avg_Grade_Adjusted_Speed_kmh AS FLOAT64) AS avg_grade_adjusted_speed_kmh,
        CAST(Pace_Zone AS INT64) AS pace_zone
    FROM {{ source('strava_raw', 'strava_activity_splits') }}
    WHERE Strava_ID IS NOT NULL AND Split_Num IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY Strava_ID, Split_Num ORDER BY Date DESC) = 1
)

SELECT * FROM raw_splits
