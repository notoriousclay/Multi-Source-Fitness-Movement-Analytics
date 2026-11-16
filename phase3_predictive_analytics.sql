-- ==============================================================================
-- File: phase3_predictive_analytics.sql
-- Project: strava-fitness-analytics (strava-sync-505308)
-- Dataset: strava_data
-- Purpose: Looker Studio Tab 4 - Predictive Modeling & Race Target Analytics
-- Includes:
--   1. Riegel's Endurance Race Predictor View (5K, 10K, Half Marathon, Marathon)
--   2. Riegel's Summary KPI View
--   3. BigQuery ML ARIMA_PLUS Weekly Running Mileage Forecast Model
--   4. Unified Historical + 8-Week Forecast View (with 90% Confidence Intervals)
-- Author: Clay (amorantoclarence@gmail.com)
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Riegel's Endurance Race Predictor View (`v_race_predictions`)
-- ------------------------------------------------------------------------------
-- Formula: T2 = T1 * (D2 / D1)^1.06
-- Automatically isolates the athlete's peak aerobic benchmark performance over
-- the preceding 60 days (runs >= 3.0 km) based on minimum 5K-equivalent time.
-- ------------------------------------------------------------------------------

CREATE OR REPLACE VIEW `strava-sync-505308.strava_data.v_race_predictions` AS
WITH recent_benchmark_runs AS (
  SELECT
    Strava_ID,
    Name,
    Date,
    Distance_km,
    Duration_min,
    Pace,
    Avg_HR,
    -- Normalized 5K equivalent time using Riegel's formula to identify true peak performance
    Duration_min * POWER(5.0 / Distance_km, 1.06) AS equiv_5k_time_min
  FROM `strava-sync-505308.strava_data.strava_activities`
  WHERE Type = 'Run'
    AND Date >= DATE_SUB(CURRENT_DATE(), INTERVAL 60 DAY)
    AND Distance_km >= 3.0
    AND Duration_min > 0
),
peak_baseline AS (
  SELECT *
  FROM recent_benchmark_runs
  ORDER BY equiv_5k_time_min ASC
  LIMIT 1
),
target_distances AS (
  SELECT '5K' AS race_name, 5.0 AS target_distance_km, 1 AS sort_order UNION ALL
  SELECT '10K' AS race_name, 10.0 AS target_distance_km, 2 AS sort_order UNION ALL
  SELECT 'Half Marathon' AS race_name, 21.0975 AS target_distance_km, 3 AS sort_order UNION ALL
  SELECT 'Marathon' AS race_name, 42.195 AS target_distance_km, 4 AS sort_order
)
SELECT
  t.race_name,
  t.target_distance_km,
  
  -- Projected Race Time in Decimal Minutes: T2 = T1 * (D2 / D1)^1.06
  ROUND(b.Duration_min * POWER(t.target_distance_km / b.Distance_km, 1.06), 2) AS projected_time_minutes,
  
  -- Projected Race Time Formatted (HH:MM:SS or MM:SS)
  CASE 
    WHEN (b.Duration_min * POWER(t.target_distance_km / b.Distance_km, 1.06)) >= 60 THEN
      FORMAT('%02d:%02d:%02d',
        CAST(FLOOR((b.Duration_min * POWER(t.target_distance_km / b.Distance_km, 1.06)) / 60) AS INT64),
        CAST(MOD(CAST(FLOOR(b.Duration_min * POWER(t.target_distance_km / b.Distance_km, 1.06)) AS INT64), 60) AS INT64),
        CAST(ROUND((b.Duration_min * POWER(t.target_distance_km / b.Distance_km, 1.06) - FLOOR(b.Duration_min * POWER(t.target_distance_km / b.Distance_km, 1.06))) * 60) AS INT64)
      )
    ELSE
      FORMAT('%02d:%02d',
        CAST(FLOOR(b.Duration_min * POWER(t.target_distance_km / b.Distance_km, 1.06)) AS INT64),
        CAST(ROUND((b.Duration_min * POWER(t.target_distance_km / b.Distance_km, 1.06) - FLOOR(b.Duration_min * POWER(t.target_distance_km / b.Distance_km, 1.06))) * 60) AS INT64)
      )
  END AS projected_time_formatted,
  
  -- Projected Pace in Decimal Minutes/km
  ROUND((b.Duration_min * POWER(t.target_distance_km / b.Distance_km, 1.06)) / t.target_distance_km, 2) AS projected_pace_decimal,
  
  -- Projected Pace Formatted (MM:SS/km)
  FORMAT('%02d:%02d/km',
    CAST(FLOOR((b.Duration_min * POWER(t.target_distance_km / b.Distance_km, 1.06)) / t.target_distance_km) AS INT64),
    CAST(ROUND((
      ((b.Duration_min * POWER(t.target_distance_km / b.Distance_km, 1.06)) / t.target_distance_km) - 
      FLOOR((b.Duration_min * POWER(t.target_distance_km / b.Distance_km, 1.06)) / t.target_distance_km)
    ) * 60) AS INT64)
  ) AS projected_pace_formatted,
  
  -- Projected Average Speed (km/h)
  ROUND(t.target_distance_km / ((b.Duration_min * POWER(t.target_distance_km / b.Distance_km, 1.06)) / 60.0), 2) AS projected_speed_kmh,
  
  -- Baseline Workout Metadata (Reference D1 and T1)
  b.Strava_ID AS baseline_strava_id,
  b.Name AS baseline_activity_name,
  b.Date AS baseline_workout_date,
  b.Distance_km AS baseline_distance_km,
  b.Duration_min AS baseline_duration_min,
  b.Pace AS baseline_pace,
  b.Avg_HR AS baseline_avg_hr,
  CURRENT_TIMESTAMP() AS calculated_at
FROM target_distances t
CROSS JOIN peak_baseline b
ORDER BY t.sort_order;


-- ------------------------------------------------------------------------------
-- 2. Riegel's Race Predictor Summary KPI View (`v_race_predictions_summary`)
-- ------------------------------------------------------------------------------
-- Formatted as a single row of KPI metrics suitable for Looker Studio scorecards.
-- ------------------------------------------------------------------------------

CREATE OR REPLACE VIEW `strava-sync-505308.strava_data.v_race_predictions_summary` AS
SELECT
  MAX(baseline_activity_name) AS baseline_activity_name,
  MAX(baseline_workout_date) AS baseline_date,
  MAX(baseline_distance_km) AS baseline_distance_km,
  MAX(baseline_pace) AS baseline_pace,
  MAX(baseline_avg_hr) AS baseline_avg_hr,
  
  -- 5K Predictions
  MAX(CASE WHEN race_name = '5K' THEN projected_time_formatted END) AS pred_5k_time,
  MAX(CASE WHEN race_name = '5K' THEN projected_pace_formatted END) AS pred_5k_pace,
  MAX(CASE WHEN race_name = '5K' THEN projected_time_minutes END) AS pred_5k_time_min,
  MAX(CASE WHEN race_name = '5K' THEN projected_speed_kmh END) AS pred_5k_speed_kmh,
  
  -- 10K Predictions
  MAX(CASE WHEN race_name = '10K' THEN projected_time_formatted END) AS pred_10k_time,
  MAX(CASE WHEN race_name = '10K' THEN projected_pace_formatted END) AS pred_10k_pace,
  MAX(CASE WHEN race_name = '10K' THEN projected_time_minutes END) AS pred_10k_time_min,
  MAX(CASE WHEN race_name = '10K' THEN projected_speed_kmh END) AS pred_10k_speed_kmh,
  
  -- Half Marathon Predictions
  MAX(CASE WHEN race_name = 'Half Marathon' THEN projected_time_formatted END) AS pred_hm_time,
  MAX(CASE WHEN race_name = 'Half Marathon' THEN projected_pace_formatted END) AS pred_hm_pace,
  MAX(CASE WHEN race_name = 'Half Marathon' THEN projected_time_minutes END) AS pred_hm_time_min,
  MAX(CASE WHEN race_name = 'Half Marathon' THEN projected_speed_kmh END) AS pred_hm_speed_kmh,

  -- Marathon Predictions
  MAX(CASE WHEN race_name = 'Marathon' THEN projected_time_formatted END) AS pred_marathon_time,
  MAX(CASE WHEN race_name = 'Marathon' THEN projected_pace_formatted END) AS pred_marathon_pace,
  MAX(CASE WHEN race_name = 'Marathon' THEN projected_time_minutes END) AS pred_marathon_time_min
FROM `strava-sync-505308.strava_data.v_race_predictions`;


-- ------------------------------------------------------------------------------
-- 3. BigQuery ML ARIMA_PLUS Weekly Mileage Forecasting Model
-- ------------------------------------------------------------------------------
-- Trains a time-series model on historical weekly running distance (2025 to present).
-- Features:
--   - Automatic ARIMA hyperparameter selection (p, d, q)
--   - Anomaly detection & cleaning of spikes/dips
--   - Time series decomposition
-- ------------------------------------------------------------------------------

CREATE OR REPLACE MODEL `strava-sync-505308.strava_data.model_weekly_mileage_forecast`
OPTIONS(
  MODEL_TYPE = 'ARIMA_PLUS',
  TIME_SERIES_TIMESTAMP_COL = 'week_start_timestamp',
  TIME_SERIES_DATA_COL = 'weekly_distance_km',
  DATA_FREQUENCY = 'WEEKLY',
  CLEAN_SPIKES_AND_DIPS = TRUE,
  DECOMPOSE_TIME_SERIES = TRUE
) AS
WITH date_bounds AS (
  SELECT 
    MIN(DATE_TRUNC(Date, WEEK(MONDAY))) AS min_week,
    DATE_TRUNC(CURRENT_DATE(), WEEK(MONDAY)) AS max_week
  FROM `strava-sync-505308.strava_data.strava_activities`
  WHERE Type = 'Run' AND Date IS NOT NULL
),
calendar_weeks AS (
  SELECT week_start
  FROM date_bounds,
  UNNEST(GENERATE_DATE_ARRAY(min_week, max_week, INTERVAL 1 WEEK)) AS week_start
),
actual_runs AS (
  SELECT
    DATE_TRUNC(Date, WEEK(MONDAY)) AS week_start,
    ROUND(SUM(Distance_km), 2) AS weekly_distance_km
  FROM `strava-sync-505308.strava_data.strava_activities`
  WHERE Type = 'Run'
  GROUP BY week_start
)
SELECT 
  TIMESTAMP(c.week_start) AS week_start_timestamp,
  COALESCE(a.weekly_distance_km, 0.0) AS weekly_distance_km
FROM calendar_weeks c
LEFT JOIN actual_runs a ON c.week_start = a.week_start;


-- ------------------------------------------------------------------------------
-- 4. Unified Historical & 8-Week Mileage Forecast View (`v_weekly_mileage_forecast`)
-- ------------------------------------------------------------------------------
-- Merges actual weekly running distance history with 8-week ML.FORECAST projections
-- and 90% confidence intervals for Looker Studio time-series combo charts.
-- ------------------------------------------------------------------------------

CREATE OR REPLACE VIEW `strava-sync-505308.strava_data.v_weekly_mileage_forecast` AS
WITH history AS (
  SELECT
    DATE(week_start_timestamp) AS week_start,
    FORMAT_DATE('%b %d', DATE(week_start_timestamp)) AS week_label,
    EXTRACT(YEAR FROM DATE(week_start_timestamp)) AS year_num,
    EXTRACT(WEEK(MONDAY) FROM DATE(week_start_timestamp)) AS week_num,
    'Actual History' AS series_type,
    ROUND(weekly_distance_km, 2) AS actual_distance_km,
    CAST(NULL AS FLOAT64) AS forecast_distance_km,
    CAST(NULL AS FLOAT64) AS lower_bound_90_pct,
    CAST(NULL AS FLOAT64) AS upper_bound_90_pct,
    CAST(NULL AS FLOAT64) AS standard_error
  FROM (
    WITH date_bounds AS (
      SELECT 
        MIN(DATE_TRUNC(Date, WEEK(MONDAY))) AS min_week,
        DATE_TRUNC(CURRENT_DATE(), WEEK(MONDAY)) AS max_week
      FROM `strava-sync-505308.strava_data.strava_activities`
      WHERE Type = 'Run' AND Date IS NOT NULL
    ),
    calendar_weeks AS (
      SELECT week_start
      FROM date_bounds,
      UNNEST(GENERATE_DATE_ARRAY(min_week, max_week, INTERVAL 1 WEEK)) AS week_start
    ),
    actual_runs AS (
      SELECT
        DATE_TRUNC(Date, WEEK(MONDAY)) AS week_start,
        ROUND(SUM(Distance_km), 2) AS weekly_distance_km
      FROM `strava-sync-505308.strava_data.strava_activities`
      WHERE Type = 'Run'
      GROUP BY week_start
    )
    SELECT 
      TIMESTAMP(c.week_start) AS week_start_timestamp,
      COALESCE(a.weekly_distance_km, 0.0) AS weekly_distance_km
    FROM calendar_weeks c
    LEFT JOIN actual_runs a ON c.week_start = a.week_start
  )
),
forecast AS (
  SELECT
    DATE(forecast_timestamp) AS week_start,
    FORMAT_DATE('%b %d', DATE(forecast_timestamp)) AS week_label,
    EXTRACT(YEAR FROM DATE(forecast_timestamp)) AS year_num,
    EXTRACT(WEEK(MONDAY) FROM DATE(forecast_timestamp)) AS week_num,
    'ARIMA+ Forecast (90% CI)' AS series_type,
    CAST(NULL AS FLOAT64) AS actual_distance_km,
    ROUND(GREATEST(0.0, forecast_value), 2) AS forecast_distance_km,
    ROUND(GREATEST(0.0, prediction_interval_lower_bound), 2) AS lower_bound_90_pct,
    ROUND(GREATEST(0.0, prediction_interval_upper_bound), 2) AS upper_bound_90_pct,
    ROUND(standard_error, 2) AS standard_error
  FROM ML.FORECAST(
    MODEL `strava-sync-505308.strava_data.model_weekly_mileage_forecast`,
    STRUCT(8 AS horizon, 0.90 AS confidence_level)
  )
)
SELECT * FROM history
UNION ALL
SELECT * FROM forecast
ORDER BY week_start;
