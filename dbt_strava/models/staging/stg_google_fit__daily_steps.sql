{{ config(materialized='view') }}

WITH raw_daily_steps AS (
    SELECT
        CAST(Date AS DATE) AS step_date,
        CAST(Total_Steps AS INT64) AS total_steps,
        Source AS source_device,
        CAST(Ingested_At AS TIMESTAMP) AS ingested_at
    FROM {{ source('strava_raw', 'daily_steps') }}
    WHERE Date IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY Date ORDER BY Ingested_At DESC) = 1
)

SELECT * FROM raw_daily_steps
