{{
    config(
        materialized='table'
    )
}}

SELECT
    shoe_name,
    first_used_date,
    last_used_date,
    total_runs,
    total_distance_km,
    total_duration_min,
    avg_pace_decimal_min,
    lifespan_threshold_km,
    remaining_distance_km,
    wear_pct,
    shoe_status
FROM {{ ref('int_shoe_mileage_metrics') }}
