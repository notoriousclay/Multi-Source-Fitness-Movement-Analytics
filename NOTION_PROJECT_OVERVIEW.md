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
   - **Gold (Production Marts)**: Delivers dimensional marts (`fct_activities`, `fct_activity_splits`, `fct_daily_health_summary`, `fct_race_predictions`, `fct_personal_bests`, `dim_shoes`, and `fct_athlete_training_journal`) validated by **44+ automated data quality tests**.
3. **Continuous All-Time Personal Bests (100m to 42km Marathon)**:
   - High-resolution sliding-window window functions and sub-second stream analytics compute all-time personal bests across **13 standard athletic distances** (`100m`, `200m`, `400m`, `800m`, `1km`, `1 mile`, `2km`, `3km`, `5km`, `10km`, `16km`, `18km`, and `21km Half Marathon`), complete with automatic future-proofing for `25km`, `30km`, `35km`, and `42km Marathon`.
4. **In-Warehouse Machine Learning & Predictive Modeling**:
   - **Riegel's Endurance Race Formula**: Computes dynamic target times and required splits for 5K, 10K, Half-Marathon, and Marathon based on rolling peak athletic performances.
   - **BigQuery ML `ARIMA_PLUS`**: Evaluates longitudinal volume trends, automated weekly seasonality, and anomaly detection.
   - **In-Warehouse Gemini LLM (`ML.GENERATE_TEXT`)**: Pre-computes microcycle, mesocycle, and macrocycle coaching narratives natively inside SQL.
5. **Autonomous Telegram AI Coach (Human-in-the-Loop Webhook)**:
   - Serverless Cloud Functions Gen 2 HTTP webhook receiving athlete voice notes, treadmill console photos, and text feedback in real-time.
   - Multimodal Gemini 2.0 Flash extracts quantitative metrics from treadmill console images and transcribes voice debriefs into structured feedback (RPE 1–10, soreness locations).
   - Dual-tier GenAI resilience: direct Google Gemini API failover to BigQuery ML's native `gemini_remote_model`.
6. **Triple-Scheduled Serverless Orchestration**:
   - Google Cloud Scheduler executes data ingestion every 8 hours (`0 */8 * * *`).
   - GitHub Actions CI/CD automatically triggers `dbt build` 30 minutes later (`30 0,8,16 * * *`), keeping all analytical marts up to date with zero manual intervention.
7. **Executive Business Intelligence**: Visualizes acute-to-chronic injury danger zones, training intensity distributions, footwear lifespan, all-time personal bests, and the interactive **Athlete Training Journal** in Google Looker Studio.

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
│ • strava_data.personal_sprint_efforts (100m, 200m, 400m, 800m sub-km sprint streams)   │
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
│    • fct_personal_bests (All-time PRs across 13 athletic distances)                    │
│    • fct_race_predictions (Riegel's 5K, 10K, HM, Marathon times)                       │
│    • dim_shoes (Equipment lifespan & retirement status)                                │
│    • fct_athlete_training_journal (Strava runs + Athlete feedback + AI feedback)       │
│                                                                                        │
│ 🛡️ 44+ Automated dbt Schema & Data Quality Tests Passing in CI/CD                     │
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
│ • 🏆 All-Time Personal Bests (100m to 21km)   │ │ • Dual-Tier Gemini ML Failover Engine│
│ • Tri-Level Synchronized AI Coaching Summaries│ └──────────────────────────────────────┘
│ • Human-in-the-Loop Athlete Training Journal  │                                        
└───────────────────────────────────────────────┘
```

---

## 🏆 Current All-Time Personal Bests (Materialized in Production)

| # | Distance Benchmark | Distance (km) | Best Time | Best Pace | Avg Heart Rate | Date Achieved | Workout Name | Shoe Used |
| :---: | :--- | :---: | :---: | :---: | :---: | :--- | :--- |
| **1** | **100 meters** | 0.10 | `00:00:14` | **02:20/km** | 168.0 bpm | 2026-11-20 | Afternoon Run | Qiaodan Leili 2.0 GT |
| **2** | **200 meters** | 0.20 | `00:00:46` | **03:50/km** | 170.0 bpm | 2026-11-20 | Afternoon Run | Qiaodan Leili 2.0 GT |
| **3** | **400 meters** | 0.40 | `00:01:43` | **04:18/km** | 172.0 bpm | 2026-11-12 | Afternoon Run | Dynafish Xiaonian |
| **4** | **800 meters** | 0.80 | `00:03:48` | **04:45/km** | 174.0 bpm | 2026-11-11 | Tempo Run | 361 Mega 3 Pro |
| **5** | **1 km** | 1.00 | `00:04:22` | **04:22/km** | 172.4 bpm | 2026-11-24 | Afternoon Run | Qiaodan Leili 2.0 GT |
| **6** | **1 mile (1.61 km)**| 1.61 | `00:08:15` | **05:08/km** | 175.0 bpm | 2026-11-11 | Tempo Run | 361 Mega 3 Pro |
| **7** | **2 km** | 2.00 | `00:10:29` | **05:15/km** | 165.6 bpm | 2026-11-11 | Tempo Run | 361 Mega 3 Pro |
| **8** | **3 km** | 3.00 | `00:16:05` | **05:22/km** | 178.8 bpm | 2026-09-20 | Afternoon Run | Dynafish Xiaonian |
| **9** | **5 km** | 5.00 | `00:27:20` | **05:28/km** | 179.0 bpm | 2026-09-20 | Afternoon Run | Dynafish Xiaonian |
| **10** | **10 km** | 10.00 | `01:02:32` | **06:15/km** | 174.6 bpm | 2026-11-20 | Afternoon Run | Qiaodan Leili 2.0 GT |
| **11** | **16 km** | 16.00 | `01:47:50` | **06:44/km** | 174.6 bpm | 2026-07-26 | MNL City Run: Aqua Run 16KM | Li-ning Feidian 6 Elite |
| **12** | **18 km** | 18.00 | `02:05:58` | **06:00/km** | 172.4 bpm | 2026-10-04 | Project Half Mary v1.0 | Li-ning Feidian 6 Elite |
| **13** | **21 km (Half Marathon)** | 20.86 | `02:27:18` | **07:04/km** | 171.8 bpm | 2026-10-04 | Project Half Mary v1.0 | Li-ning Feidian 6 Elite |

---

## 📊 dbt Medallion Architecture Breakdown

```
[Bronze: Staging Views]            [Silver: Intermediate Models]            [Gold: Production Marts]
stg_strava__activities     ───>    int_running_workload_acwr        ───>    fct_activities
stg_strava__splits         ───>    int_shoe_mileage_metrics         ───>    fct_activity_splits
stg_google_fit__steps      ───>    int_step_reconciliation          ───>    fct_daily_health_summary
stg_athlete_feedback       ─────────────────────────────────────────>    fct_race_predictions
personal_sprint_efforts    ─────────────────────────────────────────>    fct_personal_bests
                                                                            dim_shoes
                                                                            fct_athlete_training_journal
```

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

- **Production-Grade Analytics Engineering**: Complete implementation of dbt Core with 44+ automated schema/range tests, version control, and CI/CD automation.
- **Advanced Athletic Biomechanics & Stream Telemetry**: Real-world application of ACWR (Acute:Chronic Workload Ratio) for sports science injury prevention, high-resolution stream sprint extraction, and Riegel endurance race modeling.
- **Conversational Human-in-the-Loop Data Engineering**: Bridges the gap between hard telemetry (GPS/HR) and subjective athlete feedback (RPE/soreness) using serverless webhooks and NLP.
- **Cost-Optimized Architecture**: Enterprise-grade cloud data platform operating at **$0.00/month** total infrastructure cost.
