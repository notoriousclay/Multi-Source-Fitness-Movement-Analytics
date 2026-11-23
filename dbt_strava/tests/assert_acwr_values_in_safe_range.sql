-- ACWR Safety Test:
-- Acute:Chronic Workload Ratio should realistically fall between 0.0 and 4.0.
-- Anything > 4.0 indicates an abnormal data anomaly or massive data gap.
-- Returns failing rows.

SELECT
    calendar_date,
    acute_workload_7d_km,
    chronic_workload_28d_km,
    acwr_ratio
FROM {{ ref('int_running_workload_acwr') }}
WHERE acwr_ratio IS NOT NULL
  AND (acwr_ratio < 0.0 OR acwr_ratio > 4.0)
