{{
    config(
        materialized='table',
        partition_by={
            "field": "summary_date",
            "data_type": "date",
            "granularity": "day"
        }
    )
}}

WITH recon AS (
    SELECT * FROM {{ ref('int_daily_activity_step_reconciliation') }}
),

acwr AS (
    SELECT
        calendar_date,
        daily_distance_km,
        acute_workload_7d_km,
        chronic_workload_28d_km,
        acwr_ratio,
        acwr_risk_category
    FROM {{ ref('int_running_workload_acwr') }}
)

SELECT
    r.summary_date,
    r.reconciled_daily_steps,
    r.google_fit_steps,
    r.strava_steps,
    r.estimated_passive_steps,
    r.running_distance_km,
    r.active_calories,
    r.total_activities,
    w.acute_workload_7d_km,
    w.chronic_workload_28d_km,
    w.acwr_ratio,
    w.acwr_risk_category
FROM recon r
LEFT JOIN acwr w ON r.summary_date = w.calendar_date
