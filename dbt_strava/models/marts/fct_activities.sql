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
    SELECT * FROM {{ ref('stg_strava__activities') }}
),

acwr AS (
    SELECT
        calendar_date,
        acute_workload_7d_km,
        chronic_workload_28d_km,
        acwr_ratio,
        acwr_risk_category
    FROM {{ ref('int_running_workload_acwr') }}
)

SELECT
    a.strava_id,
    a.activity_date,
    a.activity_name,
    a.activity_type,
    a.distance_km,
    a.duration_min,
    a.elapsed_time_min,
    a.pace_formatted,
    a.pace_decimal_min,
    a.elevation_gain_m,
    a.calories,
    a.avg_heart_rate,
    a.cadence,
    a.activity_steps,
    a.avg_steps_per_min,
    a.avg_strides_per_min,
    a.shoe_name,
    a.city,
    a.country,
    w.acute_workload_7d_km,
    w.chronic_workload_28d_km,
    w.acwr_ratio,
    w.acwr_risk_category
FROM activities a
LEFT JOIN acwr w ON a.activity_date = w.calendar_date
