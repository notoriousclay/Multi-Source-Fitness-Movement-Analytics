-- ==============================================================================
-- File: predictive_ai_coaching_query.sql
-- Project: strava-sync-505308 | Dataset: strava_data
-- Destination Table: strava_data.ai_predictive_coaching_prescription
-- Purpose: Generates an 8-week forward-looking predictive coaching prescription
--          using BigQuery ML ARIMA_PLUS volume forecasts, historical AI performance
--          summaries (session, weekly, monthly), and Gemini (gemini_remote_model)
-- Target Goal: Sub-2 Half Marathon (< 2:00:00, 5:41/km pace) over 3 months
-- ==============================================================================

CREATE OR REPLACE TABLE `strava-sync-505308.strava_data.ai_predictive_coaching_prescription` AS
WITH historical_context AS (
  SELECT
    -- 1. Recent Session Insights (last 2 workouts)
    (SELECT STRING_AGG(CONCAT(CAST(Date AS STRING), ' (', CAST(Distance_km AS STRING), 'km @ ', Pace, ', HR: ', IFNULL(CAST(Avg_HR AS STRING), 'N/A'), '): ', SUBSTR(AI_Analysis, 1, 140)), ' | ')
     FROM (SELECT * FROM `strava-sync-505308.strava_data.ai_session_summary_results` ORDER BY Date DESC LIMIT 2)
    ) AS recent_sessions_context,
    
    -- 2. Recent Weekly Load & Consistency (last 2 weeks)
    (SELECT STRING_AGG(CONCAT(Week_Number, ' (', CAST(Weekly_Distance_km AS STRING), 'km @ ', Avg_Weekly_Pace, '): ', SUBSTR(AI_Weekly_Analysis, 1, 150)), ' | ')
     FROM (SELECT * FROM `strava-sync-505308.strava_data.ai_weekly_summary_results` ORDER BY Week_Start DESC LIMIT 2)
    ) AS recent_weeks_context,
    
    -- 3. Monthly Baseline Performance
    (SELECT CONCAT(Month_Name, ' (', CAST(Monthly_Distance_km AS STRING), 'km @ ', Avg_Monthly_Pace, '): ', SUBSTR(AI_Monthly_Analysis, 1, 200))
     FROM `strava-sync-505308.strava_data.ai_monthly_summary_results` ORDER BY Month_Start DESC LIMIT 1
    ) AS recent_month_context
),
raw_forecast AS (
  SELECT
    ROW_NUMBER() OVER (ORDER BY forecast_timestamp ASC) AS week_num_ahead,
    DATE(forecast_timestamp) AS forecast_week_start,
    DATE_ADD(DATE(forecast_timestamp), INTERVAL 6 DAY) AS forecast_week_end,
    FORMAT_DATE('%Y-W%W', DATE(forecast_timestamp)) AS iso_year_week,
    FORMAT_DATE('%b %d', DATE(forecast_timestamp)) AS week_label,
    ROUND(GREATEST(0.0, forecast_value), 1) AS arima_forecast_km,
    ROUND(GREATEST(0.0, prediction_interval_lower_bound), 1) AS arima_lower_km,
    ROUND(GREATEST(0.0, prediction_interval_upper_bound), 1) AS arima_upper_km
  FROM ML.FORECAST(
    MODEL `strava-sync-505308.strava_data.model_weekly_mileage_forecast`,
    STRUCT(8 AS horizon, 0.90 AS confidence_level)
  )
),
forecast_weeks AS (
  SELECT
    f.*,
    -- Periodized training volume progression (nudge from baseline ~14km toward 20km with deloads)
    CASE f.week_num_ahead
      WHEN 1 THEN 14.5
      WHEN 2 THEN 16.0
      WHEN 3 THEN 17.5
      WHEN 4 THEN 13.5  -- Week 4 Deload & Recovery
      WHEN 5 THEN 18.0
      WHEN 6 THEN 19.0
      WHEN 7 THEN 20.0  -- Peak Base Volume Milestone
      WHEN 8 THEN 15.0  -- Week 8 Deload & Readiness Check
    END AS target_recommended_km,
    
    -- Specific Athletic Focus per Week
    CASE f.week_num_ahead
      WHEN 1 THEN 'Base Volume Adaptation'
      WHEN 2 THEN 'Aerobic Build & Threshold Intro'
      WHEN 3 THEN 'Threshold Capacity Expansion'
      WHEN 4 THEN 'Mid-Cycle Recovery & Adaptation (Deload)'
      WHEN 5 THEN 'Volume Ceiling Push'
      WHEN 6 THEN 'Threshold Pace Consolidation'
      WHEN 7 THEN 'Peak 20km Base Volume Milestone'
      WHEN 8 THEN 'Regeneration & Fitness Test (Deload)'
    END AS phase_name
  FROM raw_forecast f
),
prompts AS (
  SELECT
    f.week_num_ahead,
    f.forecast_week_start,
    f.forecast_week_end,
    f.iso_year_week,
    f.week_label,
    f.phase_name,
    f.arima_forecast_km,
    f.arima_lower_km,
    f.arima_upper_km,
    f.target_recommended_km,
    CONCAT(
      'You are an elite sports scientist and running coach. Create a precise, actionable weekly training prescription for an athlete aiming for a Sub-2 Half Marathon (Target: < 2:00:00, 5:41/km pace). The athlete is currently predicted at 6:01/km (2:06:50 finish), leaving a 6m 50s gap (20 sec/km) to close over the next 3 months.\n\n',
      '=== ATHLETE HISTORICAL AI TELEMETRY ===\n',
      'Recent Sessions: ', h.recent_sessions_context, '\n',
      'Recent Weekly Trends: ', h.recent_weeks_context, '\n',
      'Monthly Baseline: ', h.recent_month_context, '\n\n',
      '=== THIS SPECIFIC FORECAST WEEK TARGETS ===\n',
      'Week: ', CAST(f.week_num_ahead AS STRING), ' of 8 (Starting ', CAST(f.forecast_week_start AS STRING), ' to ', CAST(f.forecast_week_end AS STRING), ')\n',
      'Training Phase: ', f.phase_name, '\n',
      'ARIMA Historical Volume Forecast: ', CAST(f.arima_forecast_km AS STRING), ' km (90% Uncertainty Band: ', CAST(f.arima_lower_km AS STRING), ' - ', CAST(f.arima_upper_km AS STRING), ' km)\n',
      'Prescribed Target Volume: ', CAST(f.target_recommended_km AS STRING), ' km (progressively nudging toward 20km ceiling)\n\n',
      '=== PRESCRIPTION INSTRUCTIONS ===\n',
      'Provide a concise 3-4 sentence training prescription for THIS WEEK ONLY:\n',
      '1. Key Quality Workout: Exact structure specifying Threshold intervals targeting 5:35/km (e.g., 3x1km or 4x1km @ 5:35/km with 90s jog recovery) or Easy tempo based on the week phase.\n',
      '2. Long Run: Recommended distance and target easy aerobic pace (6:30-6:50/km).\n',
      '3. Workload & Recovery: Managing acute-to-chronic load safely to bridge the 20 sec/km gap without overtraining.'
    ) AS prompt
  FROM forecast_weeks f
  CROSS JOIN historical_context h
)
SELECT
  p.week_num_ahead AS week_number,
  CONCAT('Week ', CAST(p.week_num_ahead AS STRING), ' (', FORMAT_DATE('%b %d', p.forecast_week_start), ' - ', FORMAT_DATE('%b %d', p.forecast_week_end), ')') AS week_display_label,
  p.forecast_week_start,
  p.forecast_week_end,
  p.phase_name AS training_phase,
  p.arima_forecast_km AS arima_volume_forecast_km,
  p.target_recommended_km AS recommended_target_volume_km,
  CONCAT(CAST(p.target_recommended_km AS STRING), ' km') AS target_volume_label,
  JSON_VALUE(ml.ml_generate_text_result, '$.candidates[0].content.parts[0].text') AS weekly_coaching_prescription,
  CURRENT_TIMESTAMP() AS generated_at
FROM ML.GENERATE_TEXT(
  MODEL `strava-sync-505308.strava_data.gemini_remote_model`,
  (SELECT * FROM prompts),
  STRUCT(0.3 AS temperature, 350 AS max_output_tokens)
) ml
JOIN prompts p ON ml.prompt = p.prompt
ORDER BY p.week_num_ahead ASC;
