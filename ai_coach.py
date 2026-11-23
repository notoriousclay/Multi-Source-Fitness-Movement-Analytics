import os
import sys
import argparse
import requests
from datetime import datetime
from dotenv import load_dotenv
from google import genai
from google.cloud import bigquery
from google.oauth2 import service_account

# Load environment
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(SCRIPT_DIR, ".env"))

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN")
TELEGRAM_CHAT_ID = os.getenv("TELEGRAM_CHAT_ID")
PROJECT_ID = os.getenv("GCP_PROJECT_ID", "strava-sync-505308")

def init_bigquery():
    creds_path = os.path.join(SCRIPT_DIR, "credentials.json")
    if os.path.exists(creds_path):
        creds = service_account.Credentials.from_service_account_file(creds_path)
        return bigquery.Client(credentials=creds, project=creds.project_id)
    return bigquery.Client(project=PROJECT_ID)

def send_telegram_message(text: str):
    """Sends a formatted message to your Telegram account."""
    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        print("⚠️ TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID not set. Message preview:")
        print(text)
        return False
    
    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
    payload = {
        "chat_id": TELEGRAM_CHAT_ID,
        "text": text,
        "parse_mode": "Markdown"
    }
    resp = requests.post(url, json=payload, timeout=10)
    if resp.status_code == 200:
        print("✅ Telegram notification dispatched successfully!")
        return True
    else:
        print(f"❌ Failed to send Telegram message: {resp.status_code} {resp.text}")
        return False

def get_gemini_client():
    if not GEMINI_API_KEY:
        raise ValueError("Missing GEMINI_API_KEY in environment or .env file.")
    return genai.Client(api_key=GEMINI_API_KEY)

# ==============================================================================
# 1. POST-RUN DEBRIEFING
# ==============================================================================
def run_post_activity_debrief(strava_id: int = None):
    """
    Fetches the latest activity + 30-day context from dbt marts,
    calls Gemini to draft a concise debrief question, and messages Telegram.
    """
    client = init_bigquery()
    
    id_clause = f"WHERE a.strava_id = {strava_id}" if strava_id else "ORDER BY a.activity_date DESC LIMIT 1"
    
    query = f"""
    WITH recent_30d AS (
        SELECT 
            ROUND(AVG(pace_decimal_min), 2) AS avg_30d_pace,
            ROUND(AVG(avg_heart_rate), 0) AS avg_30d_hr,
            ROUND(SUM(distance_km), 1) AS total_30d_km
        FROM `{PROJECT_ID}.strava_dbt_marts.fct_activities`
        WHERE activity_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
          AND activity_type = 'Run'
    )
    SELECT 
        a.strava_id,
        a.activity_date,
        a.activity_name,
        a.distance_km,
        a.duration_min,
        a.pace_formatted,
        a.pace_decimal_min,
        a.avg_heart_rate,
        a.shoe_name,
        a.elevation_gain_m,
        a.acwr_ratio,
        a.acwr_risk_category,
        r.avg_30d_pace,
        r.avg_30d_hr,
        r.total_30d_km
    FROM `{PROJECT_ID}.strava_dbt_marts.fct_activities` a
    CROSS JOIN recent_30d r
    {id_clause}
    """
    rows = list(client.query(query).result())
    if not rows:
        print("No recent running activity found to debrief.")
        return

    act = rows[0]
    prompt = f"""
    You are Clay's elite, friendly AI endurance running coach.
    Clay just completed a workout:
    - Activity: {act.activity_name} on {act.activity_date}
    - Distance: {act.distance_km} km in {act.duration_min} minutes
    - Average Pace: {act.pace_formatted} (30-day baseline pace: {act.avg_30d_pace} min/km)
    - Heart Rate: {act.avg_heart_rate or 'N/A'} bpm (30-day avg: {act.avg_30d_hr or 'N/A'} bpm)
    - Elevation Gain: {act.elevation_gain_m or 0} m
    - Footwear: {act.shoe_name or 'Default'}
    - Workload Status (ACWR): {act.acwr_ratio} ({act.acwr_risk_category})

    Write a high-impact, personal 2 to 3 sentence post-run debrief for Telegram.
    1. Acknowledge his performance relative to his 30-day baseline (e.g. pace or consistency).
    2. End with an open-ended coaching check-in question asking about his physical sensation (e.g. leg tightness, joint stiffness, energy level, or perceived exertion RPE).
    Keep it conversational, encouraging, and under 80 words.
    """
    
    gemini = get_gemini_client()
    response = gemini.models.generate_content(
        model="gemini-2.0-flash",
        contents=prompt
    )
    debrief_text = f"🏃 *Workout Debrief: {act.activity_name}*\n\n{response.text.strip()}\n\n_(Reply with a voice note or text to log your RPE & feedback)_"
    send_telegram_message(debrief_text)

# ==============================================================================
# 2. PROACTIVE HEALTH & INJURY PREVENTION ALERT (ACWR)
# ==============================================================================
def run_health_check_alert():
    """
    Evaluates acute:chronic workload ratio (ACWR). If >= 1.40, dispatches an early warning.
    """
    client = init_bigquery()
    query = f"""
    SELECT 
        summary_date,
        acute_workload_7d_km,
        chronic_workload_28d_km,
        acwr_ratio,
        acwr_risk_category
    FROM `{PROJECT_ID}.strava_dbt_marts.fct_daily_health_summary`
    WHERE summary_date = CURRENT_DATE()
      AND acwr_ratio >= 1.40
    LIMIT 1
    """
    rows = list(client.query(query).result())
    if not rows:
        print("✅ Workload check healthy (ACWR < 1.40 or within safe envelope). No alert needed.")
        return

    row = rows[0]
    alert_msg = (
        f"⚠️ *Coach Advisory: Elevated Workload Detected*\n\n"
        f"Your 7-day acute volume is *{row.acute_workload_7d_km} km* compared to your 28-day chronic baseline "
        f"of *{row.chronic_workload_28d_km} km/wk*.\n\n"
        f"• *ACWR:* `{row.acwr_ratio}` ({row.acwr_risk_category})\n\n"
        f"💡 *Recommendation:* Consider an active recovery day (light walking, mobility) or complete rest "
        f"to protect your tendons and joint health before the next high-volume block."
    )
    send_telegram_message(alert_msg)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Strava AI Coach Dispatcher")
    parser.add_argument("--mode", choices=["post_run", "health_check"], default="post_run")
    parser.add_argument("--strava_id", type=int, default=None)
    args = parser.parse_args()

    if args.mode == "post_run":
        run_post_activity_debrief(args.strava_id)
    elif args.mode == "health_check":
        run_health_check_alert()
