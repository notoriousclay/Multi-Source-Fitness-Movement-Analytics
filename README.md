# 🏃‍♂️ Strava Fitness Analytics: Enterprise Cloud ELT, dbt Medallion Lakehouse & Autonomous GenAI Coaching Platform

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
> 📝 **Notion Formatted Version:** [NOTION_PROJECT_OVERVIEW.md](file:///c:/Users/My%20PC/strava-fitness-analytics/NOTION_PROJECT_OVERVIEW.md)

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

## 🏗️ Master Architecture Flowchart

```mermaid
flowchart TD
    subgraph SOURCELAYER ["1. Multi-Source Ingestion & External APIs"]
        A["Strava API v3<br/>/athlete/activities & /gear"] -->|OAuth 2.0 Refresh Flow| EXT["Python Ingestion Engine<br/>(sync.py & sync_google_fit.py)"]
        FIT["Google Fit REST API<br/>Daily Step Aggregates"] -->|OAuth 2.0 Bearer Token| EXT
        OSM["OpenStreetMap Nominatim<br/>Reverse Geocoding"] -->|Spatial Lat/Lng Cache| EXT
    end

    subgraph SERVERLESS ["2. Serverless Cloud Compute & Webhooks"]
        CS["Google Cloud Scheduler<br/>(Cron: 0 */8 * * * Asia/Hong_Kong)"] -->|OIDC Token Trigger| GCF1["Cloud Function: strava-fitness-sync<br/>(Python 3.11 Gen 2)"]
        EXT --> GCF1
        
        TG["Telegram Mobile App<br/>(Athlete Voice/Text/Treadmill Photo)"] -->|HTTPS Webhook| GCF2["Cloud Function: strava-ai-coach-webhook<br/>(Python 3.11 Gen 2 / Serverless)"]
    end

    subgraph BRONZE ["3. Bronze Raw Data Layer (BigQuery strava_data)"]
        GCF1 -->|Sliding-Window Deduplicated Load| BQ_ACT[("strava_activities<br/>Raw Workout Telemetry")]
        GCF1 -->|Kilometer Split Ingestion| BQ_SPLITS[("strava_activity_splits<br/>Pace & Elevation Splits")]
        GCF1 -->|Daily Health Sync| BQ_STEPS[("google_fit_daily_steps<br/>Passive Ambient Steps")]
        GCF2 -->|Real-Time Feedback Ingestion| BQ_FB[("athlete_feedback<br/>RPE, Soreness, Qualitative Notes")]
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
            int_shoes["int_shoe_mileage_metrics<br/>(Shoe Wear & Degradation Tracking)"]
            int_recon["int_daily_activity_step_reconciliation<br/>(Active Workout Steps vs Passive Steps)"]
        end

        subgraph DBT_MARTS ["Gold / Production Data Marts (strava_dbt_marts)"]
            fct_act[("fct_activities<br/>Partitioned by Date, Clustered by Type/Shoe")]
            fct_splits[("fct_activity_splits<br/>Per-Kilometer Granular Splits")]
            fct_health[("fct_daily_health_summary<br/>Longitudinal Health & ACWR Risk")]
            fct_race[("fct_race_predictions<br/>Riegel's 5K, 10K, HM, Marathon Times")]
            dim_shoes[("dim_shoes<br/>Shoe Retirement Status")]
            fct_journal[("fct_athlete_training_journal<br/>Strava + Feedback + AI Coach Notes")]
        end

        BQ_ACT --> stg_act
        BQ_SPLITS --> stg_splits
        BQ_STEPS --> stg_steps
        BQ_FB --> stg_fb

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
        GHA1["GitHub Actions: deploy.yml<br/>(Sync Cloud Function CD)"]
        GHA2["GitHub Actions: deploy_telegram_webhook.yml<br/>(Webhook Cloud Function CD)"]
        GHA3["GitHub Actions: dbt_ci.yml<br/>(Cron: 30 0,8,16 * * * & PR CI)"]
        
        GHA3 -->|Runs dbt build & 47+ Schema Tests| DBT_PIPELINE
    end

    subgraph AI_PREDICTIVE ["6. Autonomous AI & In-Warehouse Intelligence"]
        BQ_MODEL["BigQuery ML: gemini_remote_model<br/>(Vertex AI gemini-2.5-flash-lite)"]
        ARIMA["BigQuery ML: arima_weekly_model<br/>(Time-Series Volume Forecasts)"]
        
        GCF2 -.->|Dual-Tier Fallback Prompting| BQ_MODEL
        GCF1 -->|Post-Run Event Trigger| COACH["ai_coach.py<br/>(Automated Post-Run Telegram Debrief)"]
        COACH --> TG
    end

    subgraph PRESENTATION ["7. Business Intelligence & Athlete Interface"]
        fct_act & fct_health & fct_race & dim_shoes & fct_journal --> LOOKER["Google Looker Studio Executive Dashboard<br/>(Interactive Visual Analytics & Training Journal)"]
        fct_health & fct_race -->|Bot Commands: /readiness, /race| TG
    end

    style SOURCELAYER fill:#fff3e0,stroke:#f57c00,stroke-width:2px;
    style SERVERLESS fill:#e3f2fd,stroke:#1976d2,stroke-width:2px;
    style BRONZE fill:#efebe9,stroke:#5d4037,stroke-width:2px;
    style DBT_PIPELINE fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px;
    style ORCHESTRATION fill:#ede7f6,stroke:#512da8,stroke-width:2px;
    style AI_PREDICTIVE fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px;
    style PRESENTATION fill:#fce4ec,stroke:#c2185b,stroke-width:2px;
```

---

## ⚡ Key Highlights & Engineering Features

### 1. Analytics Engineering with dbt Core
- **Medallion Architecture**: Strict isolation between Bronze Staging (`strava_dbt_staging`), Silver Intermediate (`strava_dbt_intermediate`), and Gold Production Marts (`strava_dbt_marts`).
- **Data Quality Assertions**: **47+ automated dbt tests** (uniqueness, not_null, accepted_values, relationships) passing in CI/CD.
- **Biomechanical Modeling**: Continuous calculation of Acute:Chronic Workload Ratios (ACWR), footwear wear curves, and daily step cross-reconciliation.

### 2. Autonomous Telegram AI Coach & Inbound Webhook
- **Serverless Cloud Function Gen 2** (`strava-ai-coach-webhook`) handling real-time athlete voice notes, text reflections, and treadmill photos.
- **Multimodal OCR**: Gemini 2.0 Flash extracts distance, pace, and duration directly from indoor treadmill screen photos and generates synthetic workouts.
- **Dual-Tier GenAI Resilience**: Direct Google Gemini API with automatic runtime failover to native BigQuery ML `gemini_remote_model`.

### 3. Serverless Cloud Economics
- **100% Free Tier**: Google Cloud Functions Gen 2, Cloud Scheduler, BigQuery, and GitHub Actions operate together at **$0.00/month**.

---

## 🏃 Quickstart & Local Execution

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

# 5. Run dbt transformations and tests locally
cd dbt_strava
dbt deps --profiles-dir .
dbt build --profiles-dir . --target dev
```

For the comprehensive technical specification, detailed schema definitions, SQL queries, and sports science algorithms, explore [documentation.md](file:///c:/Users/My%20PC/strava-fitness-analytics/documentation.md).
