{{ config(materialized='view') }}

WITH date_bounds AS (
    SELECT
        MIN(activity_date) AS min_date,
        CURRENT_DATE() AS max_date
    FROM {{ ref('stg_strava__activities') }}
    WHERE activity_type = 'Run'
),

calendar_spine AS (
    SELECT calendar_date
    FROM date_bounds,
    UNNEST(GENERATE_DATE_ARRAY(min_date, max_date, INTERVAL 1 DAY)) AS calendar_date
),

daily_run_totals AS (
    SELECT
        activity_date,
        ROUND(SUM(distance_km), 2) AS daily_distance_km,
        ROUND(SUM(duration_min), 2) AS daily_duration_min,
        COUNT(strava_id) AS run_count
    FROM {{ ref('stg_strava__activities') }}
    WHERE activity_type = 'Run'
    GROUP BY activity_date
),

joined_calendar AS (
    SELECT
        c.calendar_date,
        COALESCE(d.daily_distance_km, 0.0) AS daily_distance_km,
        COALESCE(d.daily_duration_min, 0.0) AS daily_duration_min,
        COALESCE(d.run_count, 0) AS run_count
    FROM calendar_spine c
    LEFT JOIN daily_run_totals d ON c.calendar_date = d.activity_date
),

workload_calculations AS (
    SELECT
        calendar_date,
        daily_distance_km,
        daily_duration_min,
        run_count,
        -- Acute Workload: sum of past 7 days (including current day)
        ROUND(SUM(daily_distance_km) OVER (
            ORDER BY calendar_date
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ), 2) AS acute_workload_7d_km,
        -- Chronic Workload: rolling 28-day sum normalized to weekly average (sum / 4)
        ROUND(SUM(daily_distance_km) OVER (
            ORDER BY calendar_date
            ROWS BETWEEN 27 PRECEDING AND CURRENT ROW
        ) / 4.0, 2) AS chronic_workload_28d_km
    FROM joined_calendar
),

final_acwr AS (
    SELECT
        calendar_date,
        daily_distance_km,
        daily_duration_min,
        run_count,
        acute_workload_7d_km,
        chronic_workload_28d_km,
        CASE
            WHEN chronic_workload_28d_km < 1.0 THEN NULL
            ELSE ROUND(acute_workload_7d_km / chronic_workload_28d_km, 2)
        END AS acwr_ratio,
        CASE
            WHEN chronic_workload_28d_km < 1.0 THEN 'Insufficient Chronic Baseline (<1km/wk)'
            WHEN (acute_workload_7d_km / chronic_workload_28d_km) < 0.80 THEN 'Under-training'
            WHEN (acute_workload_7d_km / chronic_workload_28d_km) BETWEEN 0.80 AND 1.30 THEN 'Optimal Range'
            WHEN (acute_workload_7d_km / chronic_workload_28d_km) BETWEEN 1.31 AND 1.50 THEN 'Caution / Elevated'
            ELSE 'High Risk / Danger'
        END AS acwr_risk_category
    FROM workload_calculations
)

SELECT * FROM final_acwr
