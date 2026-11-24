# 🏃‍♂️ Strava Fitness Analytics: Enterprise Cloud ELT, dbt Medallion Lakehouse & Autonomous GenAI Coaching Platform

> **Target Role:** Senior Data Engineer / Analytics Engineer / AI Solutions Architect  
> **Author:** Clarence Lasala ([@notoriousclay](https://github.com/notoriousclay))  
> **Repository:** [https://github.com/notoriousclay/strava-fitness-analytics](https://github.com/notoriousclay/strava-fitness-analytics)  
> **Live Looker Studio Dashboard:** [https://datastudio.google.com/s/gXCMPgKJH48](https://datastudio.google.com/s/gXCMPgKJH48)  
> **Tech Stack:** Python 3.11, Google Cloud Platform (BigQuery, Cloud Functions Gen 2, Cloud Scheduler, IAM), dbt Core (dbt-bigquery), Strava API v3, Google Fit REST API, BigQuery ML (Gemini 2.5 Flash Lite & ARIMA_PLUS), Telegram Bot API, GitHub Actions CI/CD, Google Looker Studio, OpenStreetMap Nominatim  

---

## 📌 Executive Summary

Modern endurance athletes generate rich, high-frequency telemetry across fragmented channels: GPS smartwatches (Strava), ambient physical movement trackers (Google Fit), and qualitative post-exercise physiological states (Rating of Perceived Exertion [RPE], localized muscle soreness, and systemic fatigue). Historically, this data remains trapped in isolated silos, lacks biomechanical modeling, and provides no actionable, closed-loop feedback to the runner.

This project delivers an **end-to-end, enterprise-grade Data & AI Engineering Platform** built across a robust 6-layer architecture:
1. **Multi-Source Ingestion & Enrichment**: Autonomously extracts workout telemetry from the **Strava REST API** (OAuth 2.0 automatic token rotation) and background physical movement from the **Google Fit REST API**, enriched with spatial reverse-geocoding (OpenStreetMap Nominatim) and biomechanical feature imputation.
2. **dbt Medallion Lakehouse Architecture**:
   - **Bronze (Staging)**: Cleans, types, deduplicates, and standardizes raw activities, kilometer splits, Google Fit daily step counts, and athlete debrief messages.
   - **Silver (Intermediate)**: Calculates sports-science metrics including sliding-window **Acute:Chronic Workload Ratios (ACWR)**, equipment wear/depreciation curves, and active-vs-incidental step reconciliation.
   - **Gold (Production Marts)**: Delivers dimensional marts (`fct_activities`, `fct_activity_splits`, `fct_daily_health_summary`, `fct_race_predictions`, `dim_shoes`, and `fct_athlete_training_journal`) validated by **47+ automated data quality tests**.
3. **In-Warehouse Machine Learning & Predictive Modeling**:
   - **Riegel's Endurance Race Formula**: Computes dynamic target times and required splits for 5K, 10K, Half-Marathon, and Marathon based on rolling peak athletic performances.
   - **BigQuery ML `ARIMA_PLUS`**: Evaluates longitudinal volume trends, automated weekly seasonality, and anomaly detection.
   - **In-Warehouse Gemini LLM (`ML.GENERATE_TEXT`)**: Pre-computes microcycle, mesocycle, and macrocycle coaching narratives natively inside SQL.
4. **Autonomous Telegram AI Coach (Human-in-the-Loop Webhook)**:
   - Serverless Cloud Functions Gen 2 HTTP webhook receiving athlete voice notes, treadmill console photos, and text feedback in real-time.
   - Multimodal Gemini 2.0 Flash extracts quantitative metrics from treadmill console images and transcribes voice debriefs into structured feedback (RPE 1–10, soreness locations).
   - Dual-tier GenAI resilience: direct Google Gemini API failover to BigQuery ML's native `gemini_remote_model`.
5. **Triple-Scheduled Serverless Orchestration**:
   - Google Cloud Scheduler executes data ingestion every 8 hours (`0 */8 * * *`).
   - GitHub Actions CI/CD automatically triggers `dbt build` 30 minutes later (`30 0,8,16 * * *`), keeping all analytical marts up to date with zero manual intervention.
6. **Executive Business Intelligence**: Visualizes acute-to-chronic injury danger zones, training intensity distributions, footwear lifespan, and the interactive **Athlete Training Journal** in Google Looker Studio.

---

## 🏗️ Master System Architecture Flowchart

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                        1. MULTI-SOURCE INGESTION & EXTERNAL APIS                       │
├──────────────────────────────┬─────────────────────────────┬───────────────────────────┤
│ Strava REST API v3           │ Google Fit REST API         │ OpenStreetMap Nominatim   │
│ • /athlete/activities & gear │ • Daily Passive Step Counts │ • Spatial Reverse Geocode │
│ • OAuth 2.0 Auto Token Refresh│ • OAuth 2.0 Bearer Token    │ • Coordinate Memoization  │
└──────────────┬───────────────┴──────────────┬──────────────┴─────────────┬─────────────┘
               │                              │                            │
               └──────────────────────┬───────┴────────────────────────────┘
                                      │
                                      ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                   2. SERVERLESS CLOUD FUNCTIONS & EVENT WEBHOOKS                       │
├───────────────────────────────────────────────────┬────────────────────────────────────┤
│ Google Cloud Function: strava-fitness-sync        │ Google Cloud Function: Webhook     │
│ • Python 3.11 Gen 2 / Triggered every 8 hours     │ • Python 3.11 Gen 2 Serverless     │
│ • Sliding 7-day window extraction                 │ • Receives Telegram athlete updates│
│ • Splits & Google Fit ingestion                   │ • Voice/Text RPE & Treadmill OCR   │
└─────────────────────────┬─────────────────────────┴──────────────────┬─────────────────┘
                          │                                            │
                          ▼                                            ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                        3. BIGQUERY BRONZE RAW DATA LAYER                               │
├────────────────────────────────────────────────────────────────────────────────────────┤
│ • strava_data.strava_activities          • strava_data.strava_activity_splits          │
│ • strava_data.google_fit_daily_steps     • strava_data.athlete_feedback                │
└─────────────────────────────────────────┬──────────────────────────────────────────────┘
                                          │
                                          ▼ (Scheduled dbt Build every 8 hours)
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                        4. dbt MEDALLION ANALYTICS LAKEHOUSE                            │
├────────────────────────────────────────────────────────────────────────────────────────┤
│ 🥉 BRONZE (Staging Views):                                                             │
│    • stg_strava__activities        • stg_strava__activity_splits                       │
│    • stg_google_fit__daily_steps    • stg_strava__athlete_feedback                     │
├────────────────────────────────────────────────────────────────────────────────────────┤
│ 🥈 SILVER (Intermediate Business Logic):                                               │
│    • int_running_workload_acwr (7-Day Acute vs 28-Day Chronic Rolling Workload)       │
│    • int_shoe_mileage_metrics (Footwear wear & retirement benchmarks)                  │
│    • int_daily_activity_step_reconciliation (Workout vs Passive Steps)                 │
├────────────────────────────────────────────────────────────────────────────────────────┤
│ 🥇 GOLD (Production Dimensional Marts):                                                │
│    • fct_activities (Partitioned by Date, Clustered by Type/Shoe)                      │
│    • fct_activity_splits (Granular per-kilometer splits)                               │
│    • fct_daily_health_summary (Longitudinal ACWR injury risk & total steps)            │
│    • fct_race_predictions (Riegel's 5K, 10K, HM, Marathon times)                       │
│    • dim_shoes (Equipment lifespan & retirement status)                                │
│    • fct_athlete_training_journal (Strava runs + Athlete feedback + AI feedback)       │
│                                                                                        │
│ 🛡️ 47+ Automated dbt Schema & Data Quality Tests Passing in CI/CD                     │
└─────────────────────────────────────────┬──────────────────────────────────────────────┘
                                          │
                 ┌────────────────────────┴────────────────────────┐
                 ▼                                                 ▼
┌───────────────────────────────────────────────┐ ┌──────────────────────────────────────┐
│  5. EXECUTIVE BUSINESS INTELLIGENCE (LOOKER)  │ │ 6. AUTONOMOUS TELEGRAM AI COACH      │
├───────────────────────────────────────────────┤ ├──────────────────────────────────────┤
│ • Executive Metric Scorecards & Sparklines    │ │ • Automated Post-Workout Debriefs    │
│ • Monthly Mileage & Sessions Dual-Axis Chart  │ │ • Inbound Voice Note RPE Extraction  │
│ • ACWR Injury Hazard Zone Gauge               │ │ • Treadmill Screen Multimodal OCR    │
│ • Shoe Wear & Depreciation Donut Chart        │ │ • Slash Commands: /readiness, /race  │
│ • Tri-Level Synchronized AI Coaching Summaries│ │ • Dual-Tier Gemini ML Failover Engine│
│ • Human-in-the-Loop Athlete Training Journal  │ └──────────────────────────────────────┘
└───────────────────────────────────────────────┘
```

---

## 📊 dbt Medallion Architecture Breakdown

```
[Bronze: Staging Views]            [Silver: Intermediate Models]            [Gold: Production Marts]
stg_strava__activities     ───>    int_running_workload_acwr        ───>    fct_activities
stg_strava__splits         ───>    int_shoe_mileage_metrics         ───>    fct_activity_splits
stg_google_fit__steps      ───>    int_step_reconciliation          ───>    fct_daily_health_summary
stg_athlete_feedback       ─────────────────────────────────────────>    fct_race_predictions
                                                                            dim_shoes
                                                                            fct_athlete_training_journal
```

### Bronze / Staging Models (`strava_dbt_staging`)
- **`stg_strava__activities`**: Deduplicates records using `ROW_NUMBER() OVER (PARTITION BY Strava_ID ORDER BY Ingestion_Timestamp DESC)`, casts timestamps, converts distance from meters to kilometers, formats moving pace (`MM:SS/km`), and standardizes gear IDs.
- **`stg_strava__activity_splits`**: Normalizes kilometer split intervals, calculates split elevation variance, and formats per-kilometer pace.
- **`stg_google_fit__daily_steps`**: Cleans passive daily step counts, dates, and active durations.
- **`stg_strava__athlete_feedback`**: Cleans qualitative feedback, normalizes RPE integers (1–10), soreness anatomical locations, and AI coach response logs.

### Silver / Intermediate Models (`strava_dbt_intermediate`)
- **`int_running_workload_acwr`**:
  Calculates the **Acute-to-Chronic Workload Ratio (ACWR)** using sliding window analytic functions over a generated continuous daily calendar:
  - **Acute Workload (7-Day Rolling Volume)**: Represents current physical fatigue.
  - **Chronic Workload (28-Day Rolling Average Weekly Volume)**: Represents athletic aerobic baseline fitness:
    $$\text{Chronic Workload} = \frac{\sum_{i=0}^{27} \text{Distance}_{d-i}}{4}$$
  - **ACWR Formula**:
    $$\text{ACWR} = \frac{\text{Acute Workload (7-Day km)}}{\text{Chronic Workload (28-Day Weekly km)}}$$
  - **Risk Categorization**:
    - $\text{ACWR} < 0.80$: Under-training / High Recovery
    - $0.80 \le \text{ACWR} \le 1.30$: Optimal "Sweet Spot" (Progressive Overload)
    - $1.31 \le \text{ACWR} \le 1.49$: Elevated Risk (Monitor Fatigue)
    - $\text{ACWR} \ge 1.50$: Critical Injury Hazard (Spiked Volume Danger)
- **`int_shoe_mileage_metrics`**: Aggregates running shoe depreciation, total lifetime kilometers, total sessions logged, and percentage of safe lifespan completed (assuming 650 km retirement benchmark).
- **`int_daily_activity_step_reconciliation`**: Reconciles dedicated Strava workout steps against total Google Fit daily steps to derive passive non-workout steps and total daily physical strain:
  $$\text{Incidental Steps} = \max(0, \text{Total Fit Steps} - \text{Strava Workout Steps})$$

### Gold / Production Marts (`strava_dbt_marts`)
- **`fct_activities`**: Partitioned by `activity_date` and clustered by `activity_type` and `shoe_name`. Enriched with ACWR values at the time of each run.
- **`fct_activity_splits`**: Granular kilometer breakdown for pacing consistency analysis (negative splits, fade detection).
- **`fct_daily_health_summary`**: Master daily table combining acute/chronic workload, ACWR hazard category, total daily steps, and workout counts.
- **`fct_race_predictions`**: Employs **Riegel's Endurance Formula** against the athlete's peak 5K/10K baseline to forecast race performance:
  $$T_2 = T_1 \times \left(\frac{D_2}{D_1}\right)^{1.06}$$
  Projects target times and required pacing for 5K, 10K, Half Marathon, and Full Marathon.
- **`dim_shoes`**: Equipment dimension table indicating mileage status (`Optimal`, `Moderate Wear`, `Retire Soon`, `Retired`).
- **`fct_athlete_training_journal`**: High-value human-in-the-loop mart joining Strava physical metrics (`fct_activities`) with Telegram qualitative feedback (`stg_strava__athlete_feedback`) on `strava_id` and date proximity. Displays workout stats alongside RPE, soreness, athlete voice transcripts, and AI coach recommendations.

---

## 🤖 Autonomous Telegram AI Coach & Human-in-the-Loop Webhook

### Real-Time Conversational Flow
```
                      ┌───────────────────────────────────────┐
                      │          ATHLETE (TELEGRAM)           │
                      └───────────────────┬───────────────────┘
                                          │
                  ┌───────────────────────┴───────────────────────┐
                  │ Interactive Athlete Inbound Update            │
                  ▼                                               ▼
     [Voice / Text Note Feedback]                    [Treadmill Console Photo]
                  │                                               │
                  │ HTTPS POST Payload                            │ HTTPS POST Payload
                  ▼                                               ▼
┌───────────────────────────────────────────────────────────────────────────────────┐
│              Google Cloud Function Gen 2: strava-ai-coach-webhook                 │
├───────────────────────────────────────────────────────────────────────────────────┤
│ 1. Voice/Text: Extracted via Gemini 2.0 Flash into JSON:                          │
│    { "rpe": 6, "soreness_location": "right hamstring", "fatigue_level": "moderate" }│
│ 2. Treadmill Vision OCR: Extracted console metrics:                               │
│    { "distance_km": 5.0, "duration_min": 26.5, "pace": "05:18/km", "calories": 320 }│
│ 3. Failover Resilience: If Gemini API exhausted (402), queries BigQuery ML:       │
│    SELECT ml_generate_text_result FROM ML.GENERATE_TEXT(gemini_remote_model)      │
└─────────────────────────────────┬─────────────────────────────────────────────────┘
                                  │
                                  ▼
                 ┌──────────────────────────────────┐
                 │    BigQuery: athlete_feedback    │
                 │   (Partitioned by Feedback Date) │
                 └────────────────┬─────────────────┘
                                  │
                                  ▼ (Joined in dbt)
                 ┌──────────────────────────────────┐
                 │   fct_athlete_training_journal   │
                 │     (Surfaced in Looker Studio)  │
                 └──────────────────────────────────┘
```

### Slash Commands
- `/start`: Displays welcome briefing, system capabilities, and command syntax.
- `/readiness`: Returns current 7-day acute volume, 28-day chronic baseline, ACWR ratio, and injury risk category directly from `fct_daily_health_summary`.
- `/race`: Returns current Riegel projected 5K, 10K, Half Marathon, and Marathon times from `fct_race_predictions`.

### Dual-Tier LLM Resilience Engine
To safeguard against API quota depletion or prepayment balance interruptions (HTTP 402 / 429), the bot implements **automatic runtime failover**:
- **Primary**: Direct Google Gemini API (`gemini-2.0-flash`).
- **Secondary (Zero-Downtime Fallback)**: Automatically falls back to BigQuery ML's parameterized SQL query executing `ML.GENERATE_TEXT` against `strava_data.gemini_remote_model`.

---

## ☁️ Zero-Cost Serverless Cloud Orchestration

| Component | Frequency | Trigger Method | Cost |
| :--- | :--- | :--- | :--- |
| **Strava & Google Fit Sync** | Every 8 Hours (`0 */8 * * *`) | Google Cloud Scheduler → Cloud Function (`strava-fitness-sync`) | **$0.00** (Free Tier) |
| **Telegram Coach Webhook** | On-Demand (Event-Driven) | Telegram API → Cloud Function (`strava-ai-coach-webhook`) | **$0.00** (Free Tier) |
| **dbt Build & Schema Tests** | Every 8 Hours (`30 0,8,16 * * *`) | GitHub Actions Cron Schedule (`dbt_ci.yml`) | **$0.00** (Free Tier) |
| **BigQuery Data Marts** | Continuous Query Pushdown | Google Looker Studio Connector | **$0.00** (Free Tier) |

---

## 🏆 Key Portfolio Competencies Demonstrated

- **Production-Grade Analytics Engineering**: Complete implementation of dbt Core with 47+ automated schema/range tests, version control, and CI/CD automation.
- **Advanced Athletic Biomechanics**: Real-world application of ACWR (Acute:Chronic Workload Ratio) for sports science injury prevention and Riegel endurance race modeling.
- **Conversational Human-in-the-Loop Data Engineering**: Bridges the gap between hard telemetry (GPS/HR) and subjective athlete feedback (RPE/soreness) using serverless webhooks and NLP.
- **Cost-Optimized Architecture**: Enterprise-grade cloud data platform operating at **$0.00/month** total infrastructure cost.
