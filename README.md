# 🏃‍♂️ Strava Fitness Analytics: Enterprise Cloud ELT, dbt Medallion Lakehouse & Autonomous GenAI Coaching Pipeline

[![CI/CD Multi-Pipeline](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-blue?logo=github-actions)](https://github.com/notoriousclay/strava-fitness-analytics/actions)
[![Cloud Platform](https://img.shields.io/badge/Cloud-Google%20Cloud%20Platform-orange?logo=google-cloud)](https://cloud.google.com/)
[![Data Warehouse](https://img.shields.io/badge/Data%20Warehouse-BigQuery-4285F4?logo=google-bigquery)](https://cloud.google.com/bigquery)
[![Analytics Engineering](https://img.shields.io/badge/Transformations-dbt%20Core-FF694B?logo=dbt)](https://www.getdbt.com/)
[![GenAI & ML](https://img.shields.io/badge/GenAI-Gemini%202.5%20(BigQuery%20ML)-8E75C4?logo=google-gemini)](https://deepmind.google/technologies/gemini/)
[![Telegram Bot](https://img.shields.io/badge/AI%20Coach-Telegram%20Webhook-26A5E4?logo=telegram)](https://telegram.org/)
[![BI & Visualization](https://img.shields.io/badge/BI-Google%20Looker%20Studio-E37400?logo=looker)](https://datastudio.google.com/s/gXCMPgKJH48)
[![Runtime](https://img.shields.io/badge/Python-3.11-3776AB?logo=python)](https://www.python.org/)

> 🔗 **Live Interactive Dashboard:** [Google Looker Studio Strava Dashboard](https://datastudio.google.com/s/gXCMPgKJH48)  
> 📖 **Comprehensive System Documentation:** [documentation.md](file:///c:/Users/My%20PC/strava-fitness-analytics/documentation.md)

---

## 📌 Executive Summary

Modern endurance athletes generate rich, high-frequency telemetry across disparate platforms: GPS devices (Strava), biometric background step counters (Google Fit), and qualitative post-workout perceptions (RPE, localized muscular soreness, and fatigue). Traditionally, these records exist in isolated silos or require expensive manual logging.

This project delivers an **end-to-end, enterprise-grade Data & AI Engineering Platform** that:
1. **Multi-Source Ingestion**: Autonomously extracts workout telemetry from the **Strava REST API** (OAuth 2.0 automatic token rotation) and daily background activity from the **Google Fit REST API**.
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

```mermaid
flowchart TD
    subgraph SOURCES ["1. Multi-Source Ingestion & External APIs"]
        S1["Strava REST API v3<br/>/athlete/activities & /gear"] -->|OAuth 2.0 Auto-Refresh| EXT["Python Ingestion Engine<br/>(sync.py & sync_google_fit.py)"]
        S2["Google Fit REST API<br/>Daily Step Aggregates"] -->|OAuth2 Bearer Token| EXT
        S3["OpenStreetMap Nominatim"] -->|Spatial Lat/Lng Reverse Geocoding| EXT
    end

    subgraph SERVERLESS ["2. Serverless Cloud Compute & Webhooks"]
        CS["Google Cloud Scheduler<br/>(Cron: 0 */8 * * * - Asia/Hong_Kong)"] -->|OIDC Trigger| GCF1["Cloud Function: strava-fitness-sync<br/>(Python 3.11 Gen 2)"]
        EXT --> GCF1
        
        TG["Telegram Mobile App<br/>(Athlete Voice/Text/Treadmill Photo)"] -->|HTTPS Webhook| GCF2["Cloud Function: strava-ai-coach-webhook<br/>(Python 3.11 Gen 2 / Serverless)"]
    end

    subgraph BRONZE ["3. Bronze Raw Data Layer (BigQuery strava_data)"]
        GCF1 -->|Sliding-Window Deduplicated Load| BQ_ACT[("strava_activities<br/>Raw Activity Telemetry")]
        GCF1 -->|Per-Kilometer Ingestion| BQ_SPLITS[("strava_activity_splits<br/>Pace & Elevation Splits")]
        GCF1 -->|Daily Health Sync| BQ_STEPS[("google_fit_daily_steps<br/>Passive Background Steps")]
        GCF2 -->|Real-Time Feedback Ingestion| BQ_FEEDBACK[("athlete_feedback<br/>RPE, Soreness, Qualitative Notes")]
    end

    subgraph DBT_PIPELINE ["4. Analytics Engineering Layer (dbt Core)"]
        subgraph DBT_STAGING ["Bronze / Staging Views (strava_dbt_staging)"]
            stg_act["stg_strava__activities"]
            stg_splits["stg_strava__activity_splits"]
            stg_steps["stg_google_fit__daily_steps"]
            stg_fb["stg_strava__athlete_feedback"]
        end

        subgraph DBT_INT ["Silver / Intermediate Transformations (strava_dbt_intermediate)"]
            int_acwr["int_running_workload_acwr<br/>(7d Acute vs 28d Chronic Workload)"]
            int_shoes["int_shoe_mileage_metrics<br/>(Shoe Life & Wear Degradation)"]
            int_recon["int_daily_activity_step_reconciliation<br/>(Strava Active Steps vs Fit Passive Steps)"]
        end

        subgraph DBT_MARTS ["Gold / Production Data Marts (strava_dbt_marts)"]
            fct_act[("fct_activities<br/>Partitioned by Date, Clustered by Type/Shoe")]
            fct_splits[("fct_activity_splits<br/>Deep Split Breakdown")]
            fct_health[("fct_daily_health_summary<br/>Longitudinal Health & ACWR Risk")]
            fct_race[("fct_race_predictions<br/>Riegel's 5K, 10K, HM, Marathon Times")]
            dim_shoes[("dim_shoes<br/>Equipment Retirement Tracking")]
            fct_journal[("fct_athlete_training_journal<br/>Strava + Feedback + AI Coach Notes")]
        end

        BQ_ACT --> stg_act
        BQ_SPLITS --> stg_splits
        BQ_STEPS --> stg_steps
        BQ_FEEDBACK --> stg_fb

        stg_act --> int_acwr
        stg_act --> int_shoes
        stg_act & stg_steps --> int_recon

        int_acwr & stg_act --> fct_act
        stg_splits --> fct_splits
        int_acwr & int_recon --> fct_health
        stg_act --> fct_race
        int_shoes --> dim_shoes
        fct_act & stg_fb --> fct_journal
    end

    subgraph ORCHESTRATION ["5. CI/CD & Automated Orchestration"]
        GHA1["GitHub Actions: deploy.yml<br/>(Cloud Function Sync CD)"]
        GHA2["GitHub Actions: deploy_telegram_webhook.yml<br/>(Cloud Function Webhook CD)"]
        GHA3["GitHub Actions: dbt_ci.yml<br/>(Scheduled: 30 0,8,16 * * * & PR CI)"]
        
        GHA3 -->|Runs dbt build & 47+ Schema Tests| DBT_PIPELINE
    end

    subgraph AI_PREDICTIVE ["6. Autonomous AI & In-Warehouse Intelligence"]
        BQ_MODEL["BigQuery ML: gemini_remote_model<br/>(Vertex AI gemini-2.5-flash-lite)"]
        ARIMA["BigQuery ML: arima_weekly_model<br/>(Time-Series Volume Forecasts)"]
        
        GCF2 -.->|Dual-Layer Fallback Prompting| BQ_MODEL
        GCF1 -->|Post-Run Event Trigger| COACH["ai_coach.py<br/>(Automated Post-Run Telegram Debrief)"]
        COACH --> TG
    end

    subgraph PRESENTATION ["7. Business Intelligence & Athlete Interface"]
        fct_act & fct_health & fct_race & dim_shoes & fct_journal --> LOOKER["Google Looker Studio Executive Dashboard<br/>(Interactive Visual Analytics & Training Journal)"]
        fct_health & fct_race -->|Bot Commands: /readiness, /race| TG
    end

    style SOURCES fill:#fff3e0,stroke:#f57c00,stroke-width:2px;
    style SERVERLESS fill:#e3f2fd,stroke:#1976d2,stroke-width:2px;
    style BRONZE fill:#efebe9,stroke:#5d4037,stroke-width:2px;
    style DBT_PIPELINE fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px;
    style ORCHESTRATION fill:#ede7f6,stroke:#512da8,stroke-width:2px;
    style AI_PREDICTIVE fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px;
    style PRESENTATION fill:#fce4ec,stroke:#c2185b,stroke-width:2px;
```

---

## 🚀 Key Highlights & Architectural Features

### 1. dbt Medallion Modeling
- Implemented in `dbt_strava/` with clean Bronze (Staging), Silver (Intermediate), and Gold (Marts) structure.
- **47+ automated dbt data quality tests** passing in CI on every push and daily schedule.
- Advanced metrics: **Acute-to-Chronic Workload Ratio (ACWR)**, shoe depreciation lifecycle, active vs passive step reconciliation, and Riegel race prediction algorithms.

### 2. Autonomous Telegram AI Coach & Inbound Webhook
- **Serverless Cloud Function Gen 2** (`strava-ai-coach-webhook`) receiving athlete voice debriefs, treadmill console OCR photos, and text messages.
- Real-time qualitative data extraction (RPE, soreness, fatigue) ingested straight into BigQuery `athlete_feedback`.
- Instant athlete commands: `/readiness` (ACWR injury hazard status) and `/race` (projected 5K, 10K, Half, and Marathon times).
- Dual-layer GenAI resilience: direct Google Gemini API with seamless failover to native BigQuery ML `gemini_remote_model`.

### 3. Serverless Zero-Cost Cloud Orchestration
- **Cloud Scheduler** runs daily sync 3 times a day (`0 */8 * * *`).
- **GitHub Actions** runs `dbt build` 30 minutes later (`30 0,8,16 * * *`).
- **100% Free Tier**: Operates at **$0.00 / month** across GCP Cloud Functions, BigQuery, and GitHub Actions.

---

## 🏃 Quickstart & Local Setup

```bash
# 1. Clone the repository
git clone https://github.com/notoriousclay/strava-fitness-analytics.git
cd strava-fitness-analytics

# 2. Set up virtual environment
python -m venv venv
venv\Scripts\activate

# 3. Install dependencies
pip install -r requirements.txt

# 4. Configure .env file
# Fill in STRAVA_*, TELEGRAM_*, GEMINI_*, and GCP_* credentials

# 5. Run dbt build
cd dbt_strava
dbt deps --profiles-dir .
dbt build --profiles-dir . --target dev
```

For full system architecture details, query schemas, and runbooks, read [documentation.md](file:///c:/Users/My%20PC/strava-fitness-analytics/documentation.md).
