-- Physiological pace test:
-- Returns records where pace is faster than 2:30/km (elite world record threshold)
-- or slower than 15:00/km (walking threshold) for a Run activity with distance > 0.
-- Any returned rows indicate a test failure.

SELECT
    strava_id,
    activity_date,
    activity_name,
    distance_km,
    duration_min,
    pace_decimal_min
FROM {{ ref('stg_strava__activities') }}
WHERE activity_type = 'Run'
  AND distance_km > 0.5
  AND (pace_decimal_min < 2.50 OR pace_decimal_min > 15.00)
