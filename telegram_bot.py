import os
import sys
import io
import json
import uuid
from datetime import datetime
from dotenv import load_dotenv

from google import genai
from google.genai import types
from google.cloud import bigquery
from google.oauth2 import service_account

from telegram import Update
from telegram.ext import (
    ApplicationBuilder,
    CommandHandler,
    MessageHandler,
    ContextTypes,
    filters
)

# Load configuration
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(SCRIPT_DIR, ".env"))

TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN")
TELEGRAM_CHAT_ID = os.getenv("TELEGRAM_CHAT_ID")
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
PROJECT_ID = os.getenv("GCP_PROJECT_ID", "strava-sync-505308")

def init_bigquery():
    creds_path = os.path.join(SCRIPT_DIR, "credentials.json")
    if os.path.exists(creds_path):
        creds = service_account.Credentials.from_service_account_file(creds_path)
        return bigquery.Client(credentials=creds, project=creds.project_id)
    return bigquery.Client(project=PROJECT_ID)

def get_gemini_client():
    """Initializes and returns the official Gemini client if key is set."""
    if not GEMINI_API_KEY:
        raise ValueError("Missing GEMINI_API_KEY in environment or .env file.")
    return genai.Client(api_key=GEMINI_API_KEY)

def generate_text_fallback(prompt: str) -> str:
    """Fallback text generator via BigQuery ML remote model if Gemini API credit is exhausted."""
    client = init_bigquery()
    bt = chr(96)
    q = f"""
    SELECT ml_generate_text_result
    FROM ML.GENERATE_TEXT(
      MODEL {bt}{PROJECT_ID}.strava_data.gemini_remote_model{bt},
      (SELECT @prompt_val AS prompt),
      STRUCT(0.3 AS temperature, 450 AS max_output_tokens)
    )
    """
    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("prompt_val", "STRING", prompt)
        ]
    )
    rows = list(client.query(q, job_config=job_config).result())
    if rows:
        result = rows[0].get("ml_generate_text_result", {})
        candidates = result.get("candidates", [])
        if candidates:
            parts = candidates[0].get("content", {}).get("parts", [])
            if parts:
                return parts[0].get("text", "").strip()
    return "{}"

# ==============================================================================
# 1. ATHLETE FEEDBACK EXTRACTOR (VOICE & TEXT)
# ==============================================================================
async def handle_voice_and_text(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handles athlete voice notes and text replies to debriefs."""
    user = update.effective_user
    chat_id = str(update.effective_chat.id)
    
    # Optional security filter to only listen to the owner
    if TELEGRAM_CHAT_ID and chat_id != str(TELEGRAM_CHAT_ID):
        await update.message.reply_text("⛔ Unauthorized athlete. Access restricted.")
        return

    bq_client = init_bigquery()
    raw_text = ""
    input_type = "text"

    if update.message.voice:
        input_type = "voice_note"
        await update.message.reply_chat_action("record_voice")
        voice_file = await context.bot.get_file(update.message.voice.file_id)
        audio_bytes = await voice_file.download_as_bytearray()
        
        # Multimodal audio analysis via Gemini
        prompt = """
        You are an endurance training assistant.
        Listen carefully to this audio note from the runner.
        1. Transcribe the spoken words accurately.
        2. Extract qualitative metrics as valid JSON with keys:
           - "transcript": string
           - "rpe": int (1-10 or null)
           - "soreness_location": string (e.g. "right knee", "left calf", "quads", "none")
           - "fatigue_level": string ("low", "moderate", "high")
           - "coaching_response": a supportive 1-2 sentence response confirming their feedback.
        Output ONLY the raw JSON string.
        """
        try:
            gemini = get_gemini_client()
            response = gemini.models.generate_content(
                model="gemini-2.0-flash",
                contents=[
                    types.Part.from_bytes(data=bytes(audio_bytes), mime_type="audio/ogg"),
                    prompt
                ]
            )
            raw_resp = response.text
        except Exception as e:
            raw_resp = "{}"

        try:
            cleaned = raw_resp.strip().replace("```json", "").replace("```", "").strip()
            data = json.loads(cleaned)
        except Exception:
            data = {
                "transcript": "Voice note logged",
                "rpe": None,
                "soreness_location": "unknown",
                "fatigue_level": "moderate",
                "coaching_response": "Thanks Clay! Logged your voice debrief."
            }
    else:
        # Text input
        raw_text = update.message.text
        prompt = f"""
        Analyze this post-run feedback text from runner Clay:
        "{raw_text}"
        Extract qualitative metrics as valid JSON with keys:
        - "transcript": string
        - "rpe": int (1-10 or null)
        - "soreness_location": string (e.g. "right knee", "left calf", "quads", "none")
        - "fatigue_level": string ("low", "moderate", "high")
        - "coaching_response": a supportive 1-2 sentence response confirming their feedback.
        Output ONLY the raw JSON string.
        """
        try:
            gemini = genai.Client(api_key=GEMINI_API_KEY) if GEMINI_API_KEY else None
            response = gemini.models.generate_content(
                model="gemini-2.0-flash",
                contents=prompt
            )
            raw_resp = response.text
        except Exception:
            raw_resp = generate_text_fallback(prompt)

        try:
            cleaned = raw_resp.strip().replace("```json", "").replace("```", "").strip()
            data = json.loads(cleaned)
        except Exception:
            data = {
                "transcript": raw_text,
                "rpe": None,
                "soreness_location": "unknown",
                "fatigue_level": "moderate",
                "coaching_response": "Thanks Clay! Recorded your feedback."
            }

    # Fetch latest strava_id to link
    latest_query = f"SELECT strava_id FROM `{PROJECT_ID}.strava_dbt_marts.fct_activities` ORDER BY activity_date DESC LIMIT 1"
    res = list(bq_client.query(latest_query).result())
    latest_id = res[0].strava_id if res else None

    # Write into BigQuery athlete_feedback table
    feedback_id = str(uuid.uuid4())
    row_to_insert = [{
        "feedback_id": feedback_id,
        "strava_id": latest_id,
        "feedback_timestamp": datetime.utcnow().isoformat(),
        "input_type": input_type,
        "raw_content": data.get("transcript", raw_text),
        "rpe": data.get("rpe"),
        "soreness_location": data.get("soreness_location", "none"),
        "fatigue_level": data.get("fatigue_level", "moderate"),
        "coach_followup_notes": data.get("coaching_response"),
        "ingested_at": datetime.utcnow().isoformat()
    }]
    bq_client.insert_rows_json(f"{PROJECT_ID}.strava_data.athlete_feedback", row_to_insert)

    rpe_badge = f" (RPE: {data.get('rpe')}/10)" if data.get('rpe') else ""
    soreness_badge = f" | Soreness: {data.get('soreness_location')}" if data.get('soreness_location') not in [None, "none", "unknown"] else ""
    
    reply_msg = (
        f"✅ *Feedback Logged*{rpe_badge}{soreness_badge}\n\n"
        f"_{data.get('coaching_response')}_"
    )
    await update.message.reply_markdown(reply_msg)

# ==============================================================================
# 2. MULTI-MODAL OCR INGESTION (TREADMILL CONSOLES)
# ==============================================================================
async def handle_photo(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Ingests treadmill / cardio console photos, extracts workout stats via Gemini Vision, and inserts into BigQuery."""
    photo = update.message.photo[-1] # Highest resolution
    await update.message.reply_chat_action("typing")

    photo_file = await context.bot.get_file(photo.file_id)
    image_bytes = await photo_file.download_as_bytearray()

    gemini = get_gemini_client()
    prompt = """
    You are an endurance sports OCR vision engine.
    Analyze this treadmill or cardio equipment console display photo.
    Extract the workout metrics as a clean raw JSON object with these exact keys:
    {
      "distance_km": float (e.g. 5.25),
      "duration_min": float (e.g. 28.5),
      "pace_formatted": string (MM:SS, e.g. "05:26"),
      "calories": float or null,
      "incline_pct": float or null,
      "avg_heart_rate": int or null
    }
    If distance is in miles, multiply by 1.60934 to convert to km.
    Output ONLY valid JSON without markdown wrapping.
    """
    response = gemini.models.generate_content(
        model="gemini-2.0-flash",
        contents=[
            types.Part.from_bytes(data=bytes(image_bytes), mime_type="image/jpeg"),
            prompt
        ]
    )
    try:
        cleaned = response.text.strip().replace("```json", "").replace("```", "").strip()
        stats = json.loads(cleaned)
    except Exception as e:
        await update.message.reply_text(f"⚠️ Could not clearly parse console digits. Response: {response.text[:150]}")
        return

    # Ingest synthetic workout into strava_activities
    bq_client = init_bigquery()
    synthetic_id = int(f"99{int(datetime.utcnow().timestamp())}")
    today_str = datetime.utcnow().strftime("%Y-%m-%d")

    row = [{
        "Strava_ID": synthetic_id,
        "Date": today_str,
        "Name": "Treadmill Run (OCR Sync)",
        "Type": "Run",
        "Distance_km": stats.get("distance_km", 0.0),
        "Duration_min": stats.get("duration_min", 0.0),
        "Elapsed_Time_min": stats.get("duration_min", 0.0),
        "Pace": stats.get("pace_formatted", "00:00"),
        "Elevation_m": 0.0,
        "Calories": stats.get("calories", 0.0),
        "Avg_HR": stats.get("avg_heart_rate"),
        "Gear": "Treadmill",
        "Cadence": None,
        "Total_Steps": int((stats.get("distance_km", 0.0) * 1250)), # Estimated running steps
        "Avg_Steps_Min": 165.0,
        "Avg_Strides_Min": 82.5
    }]
    bq_client.insert_rows_json(f"{PROJECT_ID}.strava_data.strava_activities", row)

    await update.message.reply_markdown(
        f"🏃 *Indoor Treadmill Run Logged!* 📸\n\n"
        f"• *Distance:* `{stats.get('distance_km')} km`\n"
        f"• *Duration:* `{stats.get('duration_min')} min`\n"
        f"• *Pace:* `{stats.get('pace_formatted')}/km`\n"
        f"• *Calories:* `{stats.get('calories') or 'N/A'}`\n"
        f"• *Incline:* `{stats.get('incline_pct') or 0.0}%`\n\n"
        f"✅ Synced directly into BigQuery (`Strava_ID: {synthetic_id}`)."
    )

# ==============================================================================
# 3. ON-DEMAND COACH COMMANDS (/coach, /readiness, /race)
# ==============================================================================
async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    msg = (
        "👋 *Welcome to your AI Endurance Running Coach!*\n\n"
        "Here is what I do for you:\n"
        "• *Post-Run Debriefs:* I automatically check in on your legs after runs.\n"
        "• *Voice Notes & Text:* Reply to me with audio or text to log RPE and muscle soreness.\n"
        "• *Treadmill OCR:* Send me a photo of your treadmill console to instantly log indoor runs.\n"
        "• *Commands:*\n"
        "  /readiness - Check your current ACWR fatigue & injury risk zone\n"
        "  /race - View your Riegel projected race times (5K, 10K, Half, Marathon)\n"
        "  /shoes - Check mileage and wear % on your shoe rotation"
    )
    await update.message.reply_markdown(msg)

async def cmd_readiness(update: Update, context: ContextTypes.DEFAULT_TYPE):
    bq_client = init_bigquery()
    q = f"""
    SELECT 
        summary_date,
        acute_workload_7d_km,
        chronic_workload_28d_km,
        acwr_ratio,
        acwr_risk_category
    FROM `{PROJECT_ID}.strava_dbt_marts.fct_daily_health_summary`
    ORDER BY summary_date DESC
    LIMIT 1
    """
    rows = list(bq_client.query(q).result())
    if not rows:
        await update.message.reply_text("No readiness records found.")
        return
    r = rows[0]
    await update.message.reply_markdown(
        f"📊 *Workload & Readiness Status ({r.summary_date})*\n\n"
        f"• *7-Day Acute Volume:* `{r.acute_workload_7d_km} km`\n"
        f"• *28-Day Chronic Baseline:* `{r.chronic_workload_28d_km} km/wk`\n"
        f"• *ACWR Ratio:* `{r.acwr_ratio}`\n"
        f"• *Status:* *{r.acwr_risk_category}*"
    )

async def cmd_race(update: Update, context: ContextTypes.DEFAULT_TYPE):
    bq_client = init_bigquery()
    q = f"SELECT race_name, projected_time_formatted, projected_pace_formatted FROM `{PROJECT_ID}.strava_dbt_marts.fct_race_predictions` ORDER BY target_distance_km"
    rows = list(bq_client.query(q).result())
    if not rows:
        await update.message.reply_text("No race predictions available.")
        return
    text = "🎯 *Riegel Endurance Race Predictions:*\n\n"
    for r in rows:
        text += f"• *{r.race_name}:* `{r.projected_time_formatted}` @ `{r.projected_pace_formatted}`\n"
    await update.message.reply_markdown(text)

def main():
    if not TELEGRAM_BOT_TOKEN:
        print("❌ Cannot start bot: TELEGRAM_BOT_TOKEN is missing from .env")
        return

    print("🤖 Starting Strava AI Coach Telegram Bot...")
    app = ApplicationBuilder().token(TELEGRAM_BOT_TOKEN).build()

    app.add_handler(CommandHandler("start", cmd_start))
    app.add_handler(CommandHandler("readiness", cmd_readiness))
    app.add_handler(CommandHandler("race", cmd_race))
    
    app.add_handler(MessageHandler(filters.PHOTO, handle_photo))
    app.add_handler(MessageHandler(filters.VOICE | (filters.TEXT & (~filters.COMMAND)), handle_voice_and_text))

    app.run_polling()

if __name__ == "__main__":
    main()
