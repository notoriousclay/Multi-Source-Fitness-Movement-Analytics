# 🏃‍♂️ Strava Fitness Analytics: Enterprise Cloud ELT, dbt Medallion Lakehouse & Autonomous GenAI Coaching Pipeline

> **Role Targeted:** Senior Data Engineer / Analytics Engineer / AI Data Solutions Specialist
> **Author:** Clarence Lasala (@notoriousclay)
> **Tech Stack:** Python 3.11, Google Cloud Platform (BigQuery, Cloud Functions Gen 2, Cloud Scheduler, IAM), dbt Core (dbt-bigquery), Strava API v3, Google Fit REST API, BigQuery ML (Gemini 2.5 Flash Lite & ARIMA_PLUS), Telegram Bot API, GitHub Actions CI/CD, Google Looker Studio
> **Live Dashboard:** https://datastudio.google.com/s/gXCMPgKJH48
> **GitHub Repository:** https://github.com/notoriousclay/strava-fitness-analytics

---

## 📌 Executive Summary

Modern endurance athletes generate rich, high-frequency telemetry across disparate platforms: GPS devices (Strava), biometric background step counters (Google Fit), and qualitative post-workout perceptions (RPE, localized muscular soreness, and fatigue). Traditionally, these records exist in isolated silos or require expensive manual logging.

This project delivers an **end-to-end, enterprise-grade Data & AI Engineering Platform** that:
1. **Multi-Source ELT Extraction**: Autonomously extracts workout telemetry from the **Strava REST API** (OAuth 2.0 automatic token rotation) and daily background activity from the **Google Fit REST API**.
2. **Reverse Geocoding & Biomechanical Enrichment**: Enriches activities with physical location data via OpenStreetMap Nominatim and biomechanical metrics (step frequencies, cadence, pace formatting).
3. **dbt Medallion Architecture (Bronze → Silver → Gold)**:
   - **Bronze (Staging)**: Cleans, types, and standardizes raw Strava activities, kilometer splits, Google Fit daily step aggregates, and qualitative athlete debriefs.
   - **Silver (Intermediate)**: Calculates acute (7-day) vs chronic (28-day) workload ratios (**ACWR**), shoe cumulative mileage and depreciation thresholds, and cross-reconciles daily step counts against logged workouts.
   - **Gold (Marts)**: Serves production analytical marts (`fct_activities`, `fct_activity_splits`, `fct_daily_health_summary`, `fct_race_predictions`, `dim_shoes`, and `fct_athlete_training_journal`) enforced with **47+ automated data quality tests**.
4. **Predictive Analytics (BigQuery ML)**:
   - **Riegel's Endurance Formula**: Models projected race times across 5K, 10K, Half-Marathon, and Marathon based on rolling peak athletic performances.
   - **ARIMA_PLUS Time-Series Forecasting**: Detects longitudinal volume trends and automated seasonality breaks.
5. **Autonomous AI Coach & Human-in-the-Loop Feedback (Telegram Webhook)**:
   - Serverless Cloud Functions Gen 2 HTTP webhook receiving real-time Telegram athlete notes, treadmill console OCR images, and voice debriefs.
   - Synthesizes qualitative metrics (RPE, soreness location, fatigue level) directly into BigQuery (`athlete_feedback`).
   - Resilient GenAI engine with dual-tier fallback: direct Gemini API with automatic failover to BigQuery ML's native `gemini_remote_model`.
6. **Triple-Scheduled Serverless Orchestration**:
   - Google Cloud Scheduler executes ingestion every 8 hours (`0 */8 * * *`).
   - GitHub Actions CI/CD automatically triggers `dbt build` 30 minutes later (`30 0,8,16 * * *`), keeping all data marts fresh with zero infrastructure cost.
7. **Business Intelligence**: Visualizes acute-to-chronic injury risk zones, training volume distributions, equipment lifespan, and the interactive **Athlete Training Journal** in Google Looker Studio.

---

## 🏗️ Master Architecture Flowchart

```
[Strava REST API v3] ──(OAuth 2.0 Auto-Refresh)──┐
[Google Fit API]    ──(OAuth 2.0 Bearer)─────────┼──> [Cloud Function: strava-fitness-sync] (Python 3.11 Gen 2)
[Nominatim Reverse] ──(Spatial Lat/Lng Geo)──────┘          │ (Scheduled every 8h: 0 */8 * * *)
                                                            ▼
                                           ┌─────────────────────────────────────────┐
                                           │  BigQuery Bronze Raw Layer (strava_data) │
                                           ├─────────────────────────────────────────┤
                                           │ • strava_activities                     │
                                           │ • strava_activity_splits                │
                                           │ • google_fit_daily_steps                │
                                           │ • athlete_feedback (from Telegram Bot)  │
                                           └───────────────────┬─────────────────────┘
                                                               │
                                                               ▼ (Triggered every 8h via GitHub Actions)
                                           ┌─────────────────────────────────────────┐
                                           │    dbt Core Medallion Lakehouse DAG     │
                                           ├─────────────────────────────────────────┤
                                           │ 1. Staging (strava_dbt_staging)         │
                                           │    - stg_strava__activities             │
                                           │    - stg_strava__activity_splits        │
                                           │    - stg_google_fit__daily_steps        │
                                           │    - stg_strava__athlete_feedback       │
                                           │                                         │
                                           │ 2. Intermediate (strava_dbt_intermediate│
                                           │    - int_running_workload_acwr (ACWR)   │
                                           │    - int_shoe_mileage_metrics           │
                                           │    - int_daily_activity_step_reconcile  │
                                           │                                         │
                                           │ 3. Production Marts (strava_dbt_marts)  │
                                           │    - fct_activities (Partitioned/Clust) │
                                           │    - fct_activity_splits                │
                                           │    - fct_daily_health_summary           │
                                           │    - fct_race_predictions (Riegel)      │
                                           │    - dim_shoes                          │
                                           │    - fct_athlete_training_journal       │
                                           │                                         │
                                           │ * 47+ Automated Schema & Range Tests *  │
                                           └───────────────────┬─────────────────────┘
                                                               │
                                 ┌─────────────────────────────┴─────────────────────────────┐
                                 ▼                                                           ▼
                ┌───────────────────────────────────┐                       ┌───────────────────────────────────┐
                │ Google Looker Studio BI Dashboard │                       │   Autonomous Telegram AI Coach    │
                ├───────────────────────────────────┤                       ├───────────────────────────────────┤
                │ • ACWR Injury Hazard Zone Gauge   │                       │ • Automated Post-Run Debriefs     │
                │ • 30-Day Moving Average Pace      │                       │ • Inbound Webhook (Cloud Run/GCF) │
                │ • Shoe Wear & Depreciation Bars   │                       │ • Voice & Text RPE/Soreness OCR   │
                │ • Athlete Training Journal Table  │                       │ • Slash Commands: /readiness,/race│
                │ • Riegel Race Predictions         │                       │ • Dual-Tier Gemini ML Fallback    │
                └───────────────────────────────────┘                       └───────────────────────────────────┘
```

---

## 📊 dbt Medallion Architecture Breakdown

### 1. Bronze / Staging (`strava_dbt_staging`)
- **`stg_strava__activities`**: Deduplicates records using `ROW_NUMBER() OVER (PARTITION BY Strava_ID ORDER BY Ingestion_Timestamp DESC)`, casts timestamps, converts distance from meters to kilometers, formats moving pace (`MM:SS/km`), and standardizes gear IDs.
- **`stg_strava__activity_splits`**: Normalizes kilometer split intervals, calculates split elevation variance, and formats per-kilometer pace.
- **`stg_google_fit__daily_steps`**: Cleans passive daily step counts, dates, and active durations.
- **`stg_strava__athlete_feedback`**: Cleans qualitative feedback, normalizes RPE integers (1–10), soreness anatomical locations, and AI coach response logs.

### 2. Silver / Intermediate (`strava_dbt_intermediate`)
- **`int_running_workload_acwr`**:
  Calculates the **Acute-to-Chronic Workload Ratio (ACWR)** using sliding window analytic functions over a generated continuous daily calendar:
  - **Acute Workload (7-Day Rolling Volume)**: Represents current physical fatigue.
  - **Chronic Workload (28-Day Rolling Average Weekly Volume)**: Represents athletic aerobic baseline fitness.
  - **ACWR Formula**:
    `ACWR = Acute_Workload_7d_km / Chronic_Workload_28d_km`
  - **Risk Categorization**:
    - `ACWR < 0.80`: Under-training / High Recovery
    - `0.80 <= ACWR <= 1.30`: Optimal "Sweet Spot" (Progressive Overload)
    - `1.31 <= ACWR <= 1.49`: Elevated Risk (Monitor Fatigue)
    - `ACWR >= 1.50`: Critical Injury Hazard (Spiked Volume Danger)
- **`int_shoe_mileage_metrics`**: Aggregates running shoe depreciation, total lifetime kilometers, total sessions logged, and percentage of safe lifespan completed (assuming 650 km retirement benchmark).
- **`int_daily_activity_step_reconciliation`**: Reconciles dedicated Strava workout steps against total Google Fit daily steps to derive passive non-workout steps and total daily physical strain.

### 3. Gold / Production Marts (`strava_dbt_marts`)
- **`fct_activities`**: Partitioned by `activity_date` and clustered by `activity_type` and `shoe_name`. Enriched with ACWR values at the time of each run.
- **`fct_activity_splits`**: Granular kilometer breakdown for pacing consistency analysis (negative splits, fade detection).
- **`fct_daily_health_summary`**: Master daily table combining acute/chronic workload, ACWR hazard category, total daily steps, and workout counts.
- **`fct_race_predictions`**: Employs **Riegel's Endurance Formula** against the athlete's peak 5K/10K baseline to forecast race performance:
  `T2 = T1 * (D2 / D1)^1.06`
  Projects target times and required pacing for 5K, 10K, Half Marathon, and Full Marathon.
- **`dim_shoes`**: Equipment dimension table indicating mileage status (`Optimal`, `Moderate Wear`, `Retire Soon`, `Retired`).
- **`fct_athlete_training_journal`**: High-value human-in-the-loop mart joining Strava physical metrics (`fct_activities`) with Telegram qualitative feedback (`stg_strava__athlete_feedback`) on `strava_id` and date proximity. Displays workout stats alongside RPE, soreness, athlete voice transcripts, and AI coach recommendations.

---

## 🤖 Autonomous Telegram AI Coach & Human-in-the-Loop Feedback

### System Flow
1. **Outbound Push (Post-Run Debrief)**:
   - When new running activities are synced, `ai_coach.py` analyzes the workout and sends an encouraging, data-driven debrief to the athlete on Telegram.
2. **Inbound Webhook (`strava-ai-coach-webhook`)**:
   - Google Cloud Functions Gen 2 serverless HTTP endpoint linked to Telegram Webhook API.
   - Athlete responds via text or voice note: *"Felt great, RPE 6, slight tightness in right hamstring."*
   - GenAI parses the message, extracts structured fields (`rpe`, `soreness_location`, `fatigue_level`), and inserts a record into BigQuery `athlete_feedback`.
3. **Treadmill Console OCR**:
   - Athlete takes a photo of an indoor cardio console (distance, duration, pace).
   - Multimodal Gemini 2.0 Flash extracts numerical metrics and writes an indoor workout row into `strava_activities` with a synthetic indoor ID (`99xxxxxxxx`).
4. **Slash Commands**:
   - `/start`: Interactive help menu.
   - `/readiness`: Returns current 7-day acute volume, 28-day chronic baseline, ACWR ratio, and injury risk category directly from `fct_daily_health_summary`.
   - `/race`: Returns current Riegel projected 5K, 10K, Half Marathon, and Marathon times from `fct_race_predictions`.
5. **Dual-Tier GenAI Resilience**:
   - Primary: Direct Google Gemini API (`gemini-2.0-flash`).
   - Fallback: Native BigQuery ML remote model (`strava_data.gemini_remote_model`) via `ML.GENERATE_TEXT` ensuring 100% uptime even if API credits are exhausted.

---

## ☁️ Zero-Cost Serverless Cloud Orchestration

| Component | Frequency | Trigger Method | Cost |
| :--- | :--- | :--- | :--- |
| **Strava & Google Fit Sync** | Every 8 Hours (`0 */8 * * *`) | Google Cloud Scheduler → Cloud Function (`strava-fitness-sync`) | **$0.00** (Free Tier) |
| **Telegram Coach Webhook** | On-Demand (Event-Driven) | Telegram API → Cloud Function (`strava-ai-coach-webhook`) | **$0.00** (Free Tier) |
| **dbt Build & Schema Tests** | Every 8 Hours (`30 0,8,16 * * *`) | GitHub Actions Cron Schedule (`dbt_ci.yml`) | **$0.00** (Free Tier) |
| **BigQuery Data Marts** | Continuous Query Pushdown | Google Looker Studio Connector | **$0.00** (Free Tier) |

---

## 🏆 Key Takeaways & Portfolio Highlights

- **Production-Grade Analytics Engineering**: Complete implementation of dbt Core with 47+ automated schema/range tests, version control, and CI/CD automation.
- **Advanced Athletic Biomechanics**: Real-world application of ACWR (Acute:Chronic Workload Ratio) for sports science injury prevention and Riegel endurance race modeling.
- **Conversational Human-in-the-Loop Data Engineering**: Bridges the gap between hard telemetry (GPS/HR) and subjective athlete feedback (RPE/soreness) using serverless webhooks and NLP.
- **Cost-Optimized Architecture**: Enterprise-grade cloud data platform operating at **$0.00/month** total infrastructure cost.
