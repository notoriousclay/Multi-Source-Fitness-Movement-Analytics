{{
    config(
        materialized='table'
    )
}}

WITH full_splits AS (
    SELECT *
    FROM {{ ref('fct_activity_splits') }}
    WHERE activity_type = 'Run' 
      AND distance_km >= 0.95 
      AND distance_km <= 1.05
),

windows AS (
    SELECT
        strava_id,
        activity_name,
        shoe_name,
        split_date,
        split_num,
        duration_sec,
        avg_heart_rate,
        
        -- 1 km
        duration_sec AS dur_1k,
        
        -- 2 km
        SUM(duration_sec) OVER w2 AS dur_2k,
        COUNT(*) OVER w2 AS cnt_2k,
        MAX(split_num) OVER w2 - split_num AS span_2k,
        AVG(avg_heart_rate) OVER w2 AS hr_2k,
        
        -- 3 km
        SUM(duration_sec) OVER w3 AS dur_3k,
        COUNT(*) OVER w3 AS cnt_3k,
        MAX(split_num) OVER w3 - split_num AS span_3k,
        AVG(avg_heart_rate) OVER w3 AS hr_3k,
        
        -- 5 km
        SUM(duration_sec) OVER w5 AS dur_5k,
        COUNT(*) OVER w5 AS cnt_5k,
        MAX(split_num) OVER w5 - split_num AS span_5k,
        AVG(avg_heart_rate) OVER w5 AS hr_5k,
        
        -- 10 km
        SUM(duration_sec) OVER w10 AS dur_10k,
        COUNT(*) OVER w10 AS cnt_10k,
        MAX(split_num) OVER w10 - split_num AS span_10k,
        AVG(avg_heart_rate) OVER w10 AS hr_10k,
        
        -- 16 km
        SUM(duration_sec) OVER w16 AS dur_16k,
        COUNT(*) OVER w16 AS cnt_16k,
        MAX(split_num) OVER w16 - split_num AS span_16k,
        AVG(avg_heart_rate) OVER w16 AS hr_16k,

        -- 18 km
        SUM(duration_sec) OVER w18 AS dur_18k,
        COUNT(*) OVER w18 AS cnt_18k,
        MAX(split_num) OVER w18 - split_num AS span_18k,
        AVG(avg_heart_rate) OVER w18 AS hr_18k
    FROM full_splits
    WINDOW
        w2 AS (PARTITION BY strava_id ORDER BY split_num ROWS BETWEEN CURRENT ROW AND 1 FOLLOWING),
        w3 AS (PARTITION BY strava_id ORDER BY split_num ROWS BETWEEN CURRENT ROW AND 2 FOLLOWING),
        w5 AS (PARTITION BY strava_id ORDER BY split_num ROWS BETWEEN CURRENT ROW AND 4 FOLLOWING),
        w10 AS (PARTITION BY strava_id ORDER BY split_num ROWS BETWEEN CURRENT ROW AND 9 FOLLOWING),
        w16 AS (PARTITION BY strava_id ORDER BY split_num ROWS BETWEEN CURRENT ROW AND 15 FOLLOWING),
        w18 AS (PARTITION BY strava_id ORDER BY split_num ROWS BETWEEN CURRENT ROW AND 17 FOLLOWING)
),

sprint_benchmarks AS (
    SELECT 
        sort_order,
        distance_label,
        distance_km,
        duration_sec,
        avg_heart_rate,
        date_achieved AS split_date,
        activity_name,
        shoe_name,
        strava_id
    FROM `{{ target.project }}.strava_data.personal_sprint_efforts`
),

split_benchmarks AS (
    -- 1 km
    SELECT 5 AS sort_order, '1 km' AS distance_label, 1.0 AS distance_km, dur_1k AS duration_sec, avg_heart_rate, split_date, activity_name, shoe_name, strava_id
    FROM windows
    
    UNION ALL
    -- 2 km
    SELECT 7, '2 km', 2.0, dur_2k, hr_2k, split_date, activity_name, shoe_name, strava_id
    FROM windows WHERE cnt_2k = 2 AND span_2k = 1
    
    UNION ALL
    -- 3 km
    SELECT 8, '3 km', 3.0, dur_3k, hr_3k, split_date, activity_name, shoe_name, strava_id
    FROM windows WHERE cnt_3k = 3 AND span_3k = 2
    
    UNION ALL
    -- 5 km
    SELECT 9, '5 km', 5.0, dur_5k, hr_5k, split_date, activity_name, shoe_name, strava_id
    FROM windows WHERE cnt_5k = 5 AND span_5k = 4
    
    UNION ALL
    -- 10 km
    SELECT 10, '10 km', 10.0, dur_10k, hr_10k, split_date, activity_name, shoe_name, strava_id
    FROM windows WHERE cnt_10k = 10 AND span_10k = 9
    
    UNION ALL
    -- 16 km
    SELECT 11, '16 km', 16.0, dur_16k, hr_16k, split_date, activity_name, shoe_name, strava_id
    FROM windows WHERE cnt_16k = 16 AND span_16k = 15

    UNION ALL
    -- 18 km
    SELECT 12, '18 km', 18.0, dur_18k, hr_18k, split_date, activity_name, shoe_name, strava_id
    FROM windows WHERE cnt_18k = 18 AND span_18k = 17
),

endurance_activities AS (
    -- 21 km (Half Marathon)
    SELECT 
        13 AS sort_order, 
        '21 km (Half Marathon)' AS distance_label, 
        ROUND(distance_km, 2) AS distance_km, 
        CAST(ROUND(duration_min * 60) AS INT64) AS duration_sec, 
        avg_heart_rate, 
        activity_date AS split_date, 
        activity_name, 
        shoe_name, 
        strava_id
    FROM {{ ref('fct_activities') }}
    WHERE activity_type = 'Run' AND distance_km >= 20.0 AND distance_km < 24.5

    UNION ALL
    -- 25 km (Future-proofed)
    SELECT 
        14, 
        '25 km', 
        ROUND(distance_km, 2), 
        CAST(ROUND(duration_min * 60) AS INT64), 
        avg_heart_rate, 
        activity_date, 
        activity_name, 
        shoe_name, 
        strava_id
    FROM {{ ref('fct_activities') }}
    WHERE activity_type = 'Run' AND distance_km >= 24.5 AND distance_km < 29.5

    UNION ALL
    -- 30 km (Future-proofed)
    SELECT 
        15, 
        '30 km', 
        ROUND(distance_km, 2), 
        CAST(ROUND(duration_min * 60) AS INT64), 
        avg_heart_rate, 
        activity_date, 
        activity_name, 
        shoe_name, 
        strava_id
    FROM {{ ref('fct_activities') }}
    WHERE activity_type = 'Run' AND distance_km >= 29.5 AND distance_km < 34.5

    UNION ALL
    -- 35 km (Future-proofed)
    SELECT 
        16, 
        '35 km', 
        ROUND(distance_km, 2), 
        CAST(ROUND(duration_min * 60) AS INT64), 
        avg_heart_rate, 
        activity_date, 
        activity_name, 
        shoe_name, 
        strava_id
    FROM {{ ref('fct_activities') }}
    WHERE activity_type = 'Run' AND distance_km >= 34.5 AND distance_km < 41.5

    UNION ALL
    -- 42 km (Marathon) (Future-proofed)
    SELECT 
        17, 
        '42 km (Marathon)', 
        ROUND(distance_km, 2), 
        CAST(ROUND(duration_min * 60) AS INT64), 
        avg_heart_rate, 
        activity_date, 
        activity_name, 
        shoe_name, 
        strava_id
    FROM {{ ref('fct_activities') }}
    WHERE activity_type = 'Run' AND distance_km >= 41.5
),

all_benchmarks AS (
    SELECT * FROM sprint_benchmarks
    UNION ALL
    SELECT * FROM split_benchmarks
    UNION ALL
    SELECT * FROM endurance_activities
),

ranked_pbs AS (
    SELECT
        sort_order,
        distance_label,
        distance_km,
        duration_sec,
        ROUND(avg_heart_rate, 1) AS avg_heart_rate,
        split_date AS date_achieved,
        activity_name,
        shoe_name,
        strava_id,
        ROW_NUMBER() OVER (PARTITION BY distance_label ORDER BY duration_sec ASC) AS rn
    FROM all_benchmarks
    WHERE duration_sec IS NOT NULL
)

SELECT
    sort_order,
    distance_label,
    distance_km,
    duration_sec,
    FORMAT('%02d:%02d:%02d',
        CAST(FLOOR(duration_sec / 3600) AS INT64),
        CAST(FLOOR(MOD(duration_sec, 3600) / 60) AS INT64),
        CAST(MOD(duration_sec, 60) AS INT64)
    ) AS best_time_formatted,
    FORMAT('%02d:%02d/km',
        CAST(FLOOR((duration_sec / distance_km) / 60) AS INT64),
        CAST(ROUND(MOD(CAST(ROUND(duration_sec / distance_km) AS INT64), 60)) AS INT64)
    ) AS best_pace_formatted,
    avg_heart_rate,
    date_achieved,
    activity_name,
    shoe_name,
    strava_id
FROM ranked_pbs
WHERE rn = 1
ORDER BY sort_order
