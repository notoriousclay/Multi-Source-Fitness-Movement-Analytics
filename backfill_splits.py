import os
import sys
import time
import requests
from datetime import datetime
from dotenv import load_dotenv
from google.cloud import bigquery
from google.oauth2 import service_account

import sync

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

load_dotenv()

def init_client():
    if os.path.exists('credentials.json'):
        creds = service_account.Credentials.from_service_account_file('credentials.json')
        proj_id = creds.project_id
        return bigquery.Client(credentials=creds, project=proj_id), proj_id
    else:
        proj_id = os.getenv("GCP_PROJECT_ID", "strava-sync-505308")
        return bigquery.Client(project=proj_id), proj_id

bq_client, PROJECT_ID = init_client()
TABLE_ID = os.getenv("BIGQUERY_TABLE_ID", f"{PROJECT_ID}.strava_data.strava_activities")
SPLITS_TABLE_ID = os.getenv("BIGQUERY_SPLITS_TABLE_ID", f"{PROJECT_ID}.strava_data.strava_activity_splits")

def backfill_splits(limit=None):
    """
    Backfills kilometer pace splits for all activities in BigQuery that are missing splits.
    Respects Strava API rate limits (15-min and daily windows).
    """
    token = sync.get_strava_access_token()
    headers = {"Authorization": f"Bearer {token}"}

    query = f"""
    SELECT DISTINCT Strava_ID, Date, Name, Type
    FROM `{TABLE_ID}`
    WHERE Strava_ID NOT IN (SELECT DISTINCT Strava_ID FROM `{SPLITS_TABLE_ID}`)
    ORDER BY Date DESC
    """
    if limit:
        query += f" LIMIT {limit}"

    print(f"🔍 Querying activities missing splits from `{TABLE_ID}`...", flush=True)
    pending_activities = list(bq_client.query(query).result())
    total_pending = len(pending_activities)
    print(f"📊 Found {total_pending} activities needing split backfill.", flush=True)

    if total_pending == 0:
        print("🎉 All activities already have splits populated in BigQuery!", flush=True)
        return 0

    all_splits_to_insert = []
    processed_count = 0

    for idx, act in enumerate(pending_activities, 1):
        act_id = act.Strava_ID
        date_str = str(act.Date)
        act_name = act.Name or "Workout"

        # Rate-limiting safety check
        while True:
            try:
                detail_url = f"https://www.strava.com/api/v3/activities/{act_id}"
                res = requests.get(detail_url, headers=headers, timeout=10)

                # Monitor Strava rate limit usage
                usage_header = res.headers.get("X-RateLimit-Usage")  # e.g., "12,45"
                limit_header = res.headers.get("X-RateLimit-Limit")  # e.g., "200,2000"
                if usage_header and limit_header:
                    try:
                        short_term_usage = int(usage_header.split(",")[0].strip())
                        short_term_limit = int(limit_header.split(",")[0].strip())
                        if short_term_usage >= (short_term_limit - 5):
                            print(f"⏳ Approaching Strava 15-min rate limit ({short_term_usage}/{short_term_limit}). Pausing for 60 seconds...", flush=True)
                            time.sleep(60)
                            continue
                    except Exception:
                        pass

                if res.status_code == 429:
                    print("⚠️ Strava API rate limit (429) encountered. Pausing for 60 seconds...", flush=True)
                    time.sleep(60)
                    continue

                if res.status_code == 200:
                    detailed_data = res.json()
                    splits = detailed_data.get("splits_metric") or []
                    parsed = sync.parse_activity_splits(act_id, date_str, splits)
                    all_splits_to_insert.extend(parsed)
                    print(f"[{idx}/{total_pending}] Strava_ID {act_id} ({act_name}): {len(parsed)} splits found.", flush=True)
                    break
                else:
                    print(f"[{idx}/{total_pending}] ⚠️ Could not fetch activity {act_id} (HTTP {res.status_code})", flush=True)
                    break
            except Exception as e:
                print(f"[{idx}/{total_pending}] ⚠️ Error fetching activity {act_id}: {e}", flush=True)
                break

        processed_count += 1
        time.sleep(0.2)  # Gentle spacing between API calls

        # Flush batch to BigQuery every 50 activities to save progress
        if len(all_splits_to_insert) >= 200:
            print(f"🚀 Inserting batch of {len(all_splits_to_insert)} splits into `{SPLITS_TABLE_ID}`...", flush=True)
            errors = bq_client.insert_rows_json(SPLITS_TABLE_ID, all_splits_to_insert)
            if errors:
                print(f"❌ Batch insertion errors: {errors}", flush=True)
            else:
                print(f"✅ Successfully inserted batch into `{SPLITS_TABLE_ID}`.", flush=True)
            all_splits_to_insert = []

    # Final flush
    if all_splits_to_insert:
        print(f"🚀 Inserting remaining {len(all_splits_to_insert)} splits into `{SPLITS_TABLE_ID}`...", flush=True)
        errors = bq_client.insert_rows_json(SPLITS_TABLE_ID, all_splits_to_insert)
        if errors:
            print(f"❌ Final batch insertion errors: {errors}", flush=True)
        else:
            print(f"✅ Successfully inserted {len(all_splits_to_insert)} splits into `{SPLITS_TABLE_ID}`.", flush=True)

    print(f"\n🎉 Backfill complete! Processed {processed_count} activities.", flush=True)
    return processed_count

if __name__ == "__main__":
    backfill_splits()
