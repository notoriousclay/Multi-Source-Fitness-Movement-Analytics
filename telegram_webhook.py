import os
import io
import json
import uuid
import asyncio
from datetime import datetime
from dotenv import load_dotenv

import functions_framework
from google import genai
from google.genai import types
from google.cloud import bigquery
from google.oauth2 import service_account

from telegram import Update
from telegram.ext import ApplicationBuilder

# Load environment
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

# Global bot application instance
bot_app = None

def get_bot_app():
    global bot_app
    if bot_app is None:
        bot_app = ApplicationBuilder().token(TELEGRAM_BOT_TOKEN).build()
    return bot_app

async def process_telegram_update(update_dict: dict):
    """Processes incoming Telegram webhook payload asynchronously."""
    app = get_bot_app()
    async with app:
        update = Update.de_json(update_dict, app.bot)
        if not update or not update.effective_chat:
            return

        chat_id = str(update.effective_chat.id)
        if TELEGRAM_CHAT_ID and chat_id != str(TELEGRAM_CHAT_ID):
            await app.bot.send_message(chat_id=chat_id, text="⛔ Unauthorized athlete. Access restricted.")
            return

        # 1. Handle Slash Commands
        if update.message and update.message.text and update.message.text.startswith("/"):
            cmd = update.message.text.split()[0].lower()
            if cmd == "/start":
                msg = (
                    "👋 *Welcome to your Cloud-Hosted AI Running Coach!*\n\n"
                    "• *Commands:*\n"
                    "  /readiness - Check acute vs chronic workload & injury risk\n"
                    "  /race - View Riegel projected race times\n"
                    "• *Voice/Text:* Send notes after your run to log RPE and soreness.\n"
                    "• *Treadmill OCR:* Send a photo of any treadmill screen to ingest your run!"
                )
                await app.bot.send_message(chat_id=chat_id, text=msg, parse_mode="Markdown")
                return

            elif cmd == "/readiness":
                bq_client = init_bigquery()
                q = f"""
                SELECT summary_date, acute_workload_7d_km, chronic_workload_28d_km, acwr_ratio, acwr_risk_category
                FROM `{PROJECT_ID}.strava_dbt_marts.fct_daily_health_summary`
                ORDER BY summary_date DESC LIMIT 1
                """
                rows = list(bq_client.query(q).result())
                if rows:
                    r = rows[0]
                    await app.bot.send_message(
                        chat_id=chat_id,
                        text=(
                            f"📊 *Workload & Readiness Status ({r.summary_date})*\n\n"
                            f"• *7-Day Acute Volume:* `{r.acute_workload_7d_km} km`\n"
                            f"• *28-Day Chronic Baseline:* `{r.chronic_workload_28d_km} km/wk`\n"
                            f"• *ACWR Ratio:* `{r.acwr_ratio}`\n"
                            f"• *Status:* *{r.acwr_risk_category}*"
                        ),
                        parse_mode="Markdown"
                    )
                return

            elif cmd == "/race":
                bq_client = init_bigquery()
                q = f"SELECT race_name, projected_time_formatted, projected_pace_formatted FROM `{PROJECT_ID}.strava_dbt_marts.fct_race_predictions` ORDER BY target_distance_km"
                rows = list(bq_client.query(q).result())
                text = "🎯 *Riegel Endurance Race Predictions:*\n\n"
                for r in rows:
                    text += f"• *{r.race_name}:* `{r.projected_time_formatted}` @ `{r.projected_pace_formatted}`\n"
                await app.bot.send_message(chat_id=chat_id, text=text, parse_mode="Markdown")
                return

        # 2. Handle Treadmill Photo (OCR Vision)
        if update.message and update.message.photo:
            photo = update.message.photo[-1]
            photo_file = await app.bot.get_file(photo.file_id)
            image_bytes = await photo_file.download_as_bytearray()

            gemini = get_gemini_client()
            prompt = """
            You are an endurance sports OCR vision engine.
            Analyze this treadmill or cardio equipment console display photo.
            Extract the workout metrics as a clean raw JSON object with these exact keys:
            {
              "distance_km": float,
              "duration_min": float,
              "pace_formatted": string (MM:SS),
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
            except Exception:
                await app.bot.send_message(chat_id=chat_id, text="⚠️ Could not parse console digits clearly. Please check lighting.")
                return

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
                "Total_Steps": int((stats.get("distance_km", 0.0) * 1250)),
                "Avg_Steps_Min": 165.0,
                "Avg_Strides_Min": 82.5
            }]
            bq_client.insert_rows_json(f"{PROJECT_ID}.strava_data.strava_activities", row)

            await app.bot.send_message(
                chat_id=chat_id,
                text=(
                    f"🏃 *Indoor Treadmill Run Logged!* 📸\n\n"
                    f"• *Distance:* `{stats.get('distance_km')} km`\n"
                    f"• *Duration:* `{stats.get('duration_min')} min`\n"
                    f"• *Pace:* `{stats.get('pace_formatted')}/km`\n"
                    f"• *Calories:* `{stats.get('calories') or 'N/A'}`\n"
                    f"• *Incline:* `{stats.get('incline_pct') or 0.0}%`\n\n"
                    f"✅ Synced directly into BigQuery (`Strava_ID: {synthetic_id}`)."
                ),
                parse_mode="Markdown"
            )
            return

        # 3. Handle Voice & Text Notes (Athlete Feedback)
        if update.message and (update.message.voice or update.message.text):
            input_type = "text"
            raw_text = update.message.text or ""

            if update.message.voice:
                input_type = "voice_note"
                voice_file = await app.bot.get_file(update.message.voice.file_id)
                audio_bytes = await voice_file.download_as_bytearray()
                prompt = """
                You are an endurance training assistant.
                Listen carefully to this audio note from the runner.
                1. Transcribe the spoken words accurately.
                2. Extract qualitative metrics as valid JSON with keys:
                   - "transcript": string
                   - "rpe": int (1-10 or null)
                   - "soreness_location": string (e.g. "right knee", "left calf", "none")
                   - "fatigue_level": string ("low", "moderate", "high")
                   - "coaching_response": a supportive 1-2 sentence response.
                Output ONLY raw JSON string.
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
                except Exception:
                    raw_resp = "{}"

                try:
                    data = json.loads(raw_resp.strip().replace("```json", "").replace("```", "").strip())
                except Exception:
                    data = {"transcript": "Voice note logged", "rpe": None, "soreness_location": "unknown", "coaching_response": "Thanks Clay! Logged your voice debrief."}
            else:
                prompt = f"""
                Analyze this post-run feedback text from runner Clay:
                "{raw_text}"
                Extract qualitative metrics as valid JSON with keys:
                - "transcript": string
                - "rpe": int (1-10 or null)
                - "soreness_location": string
                - "fatigue_level": string
                - "coaching_response": a supportive 1-2 sentence response confirming their feedback.
                Output ONLY the raw JSON string.
                """
                try:
                    gemini = get_gemini_client()
                    response = gemini.models.generate_content(model="gemini-2.0-flash", contents=prompt)
                    raw_resp = response.text
                except Exception:
                    raw_resp = generate_text_fallback(prompt)

                try:
                    data = json.loads(raw_resp.strip().replace("```json", "").replace("```", "").strip())
                except Exception:
                    data = {"transcript": raw_text, "rpe": None, "soreness_location": "none", "coaching_response": "Thanks Clay! Recorded your feedback."}

            bq_client = init_bigquery()
            latest_query = f"SELECT strava_id FROM `{PROJECT_ID}.strava_dbt_marts.fct_activities` ORDER BY activity_date DESC LIMIT 1"
            res = list(bq_client.query(latest_query).result())
            latest_id = res[0].strava_id if res else None

            row_to_insert = [{
                "feedback_id": str(uuid.uuid4()),
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

            rpe_badge = f" (RPE: {data.get('rpe')}/10)" if data.get("rpe") else ""
            soreness_badge = f" | Soreness: {data.get('soreness_location')}" if data.get("soreness_location") not in [None, "none", "unknown"] else ""

            await app.bot.send_message(
                chat_id=chat_id,
                text=(
                    f"✅ *Feedback Logged*{rpe_badge}{soreness_badge}\n\n"
                    f"_{data.get('coaching_response')}_"
                ),
                parse_mode="Markdown"
            )

@functions_framework.http
def telegram_webhook(request):
    """Cloud Function / Cloud Run HTTP webhook entry point for Telegram updates."""
    if request.method != "POST":
        return ("Method Not Allowed", 405)

    try:
        update_json = request.get_json(silent=True)
        if not update_json:
            return ("No payload", 400)

        asyncio.run(process_telegram_update(update_json))
        return ("OK", 200)
    except Exception as e:
        print(f"❌ Error processing Telegram webhook: {e}")
        return ("Internal Server Error", 500)
