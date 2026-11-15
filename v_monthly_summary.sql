-- ==============================================================================
-- File: v_monthly_summary.sql
-- Project: strava-fitness-analytics (strava-sync-505308)
-- Dataset: strava_data
-- Purpose: Analytical views for Looker Studio Tab 3 (Monthly Trends & Shoe Health)
-- Author: Clay (amorantoclarence@gmail.com)
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Monthly Performance & Step Reconciliation Summary View
-- ------------------------------------------------------------------------------
-- Consolidates Strava workout telemetry and Google Fit daily passive steps into
-- a unified monthly grain (1 row per calendar month).
-- Provides volume, elevation, heart rate, running pace, and MoM growth metrics.
-- ------------------------------------------------------------------------------

CREATE OR REPLACE VIEW `strava-sync-505308.strava_data.v_monthly_summary` AS
WITH strava_monthly AS (
    SELECT
        DATE_TRUNC(Date, MONTH)                                     AS month_start,
        LAST_DAY(Date, MONTH)                                       AS month_end,
        FORMAT_DATE('%B', Date)                                     AS month_name,
        EXTRACT(MONTH FROM Date)                                    AS month_num,
        EXTRACT(YEAR FROM Date)                                     AS year_num,
        FORMAT_DATE('%b %Y', Date)                                  AS month_label,
        COUNT(Strava_ID)                                            AS total_sessions,
        COUNTIF(Type = 'Run')                                       AS total_runs,
        COUNTIF(Type = 'Walk')                                      AS total_walks,
        COUNTIF(Type = 'Ride')                                      AS total_rides,
        COUNT(DISTINCT Date)                                        AS active_workout_days,
        ROUND(SUM(Distance_km), 2)                                  AS monthly_distance_km,
        ROUND(SUM(CASE WHEN Type = 'Run'  THEN Distance_km ELSE 0 END), 2) AS run_distance_km,
        ROUND(SUM(CASE WHEN Type = 'Walk' THEN Distance_km ELSE 0 END), 2) AS walk_distance_km,
        ROUND(SUM(CASE WHEN Type = 'Ride' THEN Distance_km ELSE 0 END), 2) AS ride_distance_km,
        ROUND(AVG(Distance_km), 2)                                  AS avg_session_distance_km,
        ROUND(SUM(Duration_min), 1)                                 AS monthly_duration_min,
        ROUND(SUM(Duration_min) / 60.0, 1)                          AS monthly_duration_hours,
        ROUND(SUM(Elevation_m), 1)                                  AS monthly_elevation_m,
        ROUND(AVG(CASE WHEN Avg_HR > 0 THEN Avg_HR END), 1)         AS avg_heart_rate,
        ROUND(AVG(CASE WHEN Cadence > 0 THEN Cadence END), 1)       AS avg_cadence,
        CAST(SUM(Calories) AS INT64)                                AS total_calories,
        
        -- Running Pace Calculations (Decimal and MM:SS format)
        ROUND(SAFE_DIVIDE(
            SUM(CASE WHEN Type = 'Run' THEN Duration_min ELSE 0 END), 
            SUM(CASE WHEN Type = 'Run' THEN Distance_km ELSE 0 END)
        ), 2) AS avg_run_pace_decimal,
        
        FORMAT('%02d:%02d/km',
            CAST(FLOOR(SAFE_DIVIDE(
                SUM(CASE WHEN Type = 'Run' THEN Duration_min ELSE 0 END), 
                SUM(CASE WHEN Type = 'Run' THEN Distance_km ELSE 0 END)
            )) AS INT64),
            CAST(ROUND((SAFE_DIVIDE(
                SUM(CASE WHEN Type = 'Run' THEN Duration_min ELSE 0 END), 
                SUM(CASE WHEN Type = 'Run' THEN Distance_km ELSE 0 END)
            ) - FLOOR(SAFE_DIVIDE(
                SUM(CASE WHEN Type = 'Run' THEN Duration_min ELSE 0 END), 
                SUM(CASE WHEN Type = 'Run' THEN Distance_km ELSE 0 END)
            ))) * 60) AS INT64)
        ) AS avg_run_pace_formatted,
        
        STRING_AGG(DISTINCT Gear, ', ')                             AS shoes_used
    FROM `strava-sync-505308.strava_data.strava_activities`
    WHERE Date IS NOT NULL
    GROUP BY month_start, month_end, month_name, month_num, year_num, month_label
),
fit_monthly AS (
    SELECT
        DATE_TRUNC(Date, MONTH)                                     AS month_start,
        SUM(total_daily_steps)                                      AS total_monthly_steps,
        SUM(raw_fit_steps)                                          AS total_raw_fit_steps,
        SUM(unrecorded_step_buffer)                                 AS total_buffer_steps,
        SUM(workout_steps)                                          AS total_workout_steps,
        SUM(incidental_steps)                                       AS total_incidental_steps,
        ROUND(AVG(total_daily_steps), 0)                            AS avg_daily_steps,
        COUNT(Date)                                                 AS days_step_tracked
    FROM `strava-sync-505308.strava_data.v_daily_step_reconciliation`
    GROUP BY month_start
)
SELECT 
    s.month_start,
    s.month_end,
    s.month_name,
    s.month_num,
    s.year_num,
    s.month_label,
    s.total_sessions,
    s.total_runs,
    s.total_walks,
    s.total_rides,
    s.active_workout_days,
    s.monthly_distance_km,
    s.run_distance_km,
    s.walk_distance_km,
    s.ride_distance_km,
    s.avg_session_distance_km,
    s.monthly_duration_min,
    s.monthly_duration_hours,
    s.monthly_elevation_m,
    s.avg_heart_rate,
    s.avg_cadence,
    s.total_calories,
    s.avg_run_pace_decimal,
    s.avg_run_pace_formatted,
    s.shoes_used,
    
    -- Passive Steps & Reconciliation (from Google Fit + 1k daily buffer)
    COALESCE(f.total_monthly_steps, 0)                              AS total_monthly_steps,
    COALESCE(f.avg_daily_steps, 0)                                  AS avg_daily_steps,
    COALESCE(f.total_workout_steps, 0)                              AS total_workout_steps,
    COALESCE(f.total_incidental_steps, 0)                           AS total_incidental_steps,
    COALESCE(f.days_step_tracked, 0)                                AS days_step_tracked,
    
    -- Month-over-Month (MoM) Growth Telemetry
    LAG(s.monthly_distance_km, 1) OVER (ORDER BY s.month_start)     AS prev_month_distance_km,
    ROUND(
        (s.monthly_distance_km - LAG(s.monthly_distance_km, 1) OVER (ORDER BY s.month_start)) / 
        NULLIF(LAG(s.monthly_distance_km, 1) OVER (ORDER BY s.month_start), 0) * 100, 
        1
    ) AS mom_distance_growth_pct
FROM strava_monthly s
LEFT JOIN fit_monthly f 
    ON s.month_start = f.month_start
ORDER BY s.month_start DESC;


-- ------------------------------------------------------------------------------
-- 2. Shoe Lifecycle & Depreciation Tracking View
-- ------------------------------------------------------------------------------
-- Computes lifetime cumulative mileage, wear percentage against the standard 700 km
-- retirement threshold, remaining mileage, and qualitative status per shoe model.
-- Powers Visual 4 (Shoe Depreciation Table) in Looker Studio Tab 3.
-- ------------------------------------------------------------------------------

CREATE OR REPLACE VIEW `strava-sync-505308.strava_data.v_shoe_depreciation` AS
SELECT
    Gear                                                            AS shoe_name,
    COUNT(Strava_ID)                                                AS total_sessions,
    ROUND(SUM(Distance_km), 2)                                      AS total_distance_km,
    ROUND(SUM(Duration_min) / 60.0, 1)                              AS total_hours,
    ROUND(AVG(CASE WHEN Avg_HR > 0 THEN Avg_HR END), 1)             AS avg_heart_rate,
    ROUND((SUM(Distance_km) / 700.0) * 100, 1)                      AS wear_pct,
    GREATEST(0.0, ROUND(700.0 - SUM(Distance_km), 1))               AS remaining_km_to_700,
    CASE 
        WHEN SUM(Distance_km) < 500 THEN 'Fresh (<500km)'
        WHEN SUM(Distance_km) < 650 THEN 'Mid-life (500-650km)'
        ELSE 'Replace Soon (>650km)'
    END                                                             AS shoe_status,
    MIN(Date)                                                       AS first_used_date,
    MAX(Date)                                                       AS last_used_date
FROM `strava-sync-505308.strava_data.strava_activities`
WHERE Gear IS NOT NULL AND Gear != ''
GROUP BY Gear
ORDER BY total_distance_km DESC;
