import math
import os
import sys
import time
import requests
from datetime import datetime, timedelta
from dotenv import load_dotenv
from google.cloud import bigquery
from google.oauth2 import service_account

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

GEO_CACHE = {}
GEAR_CACHE = {}

def get_gear_name(gear_id, access_token):
    if not gear_id or not access_token:
        return None
    if gear_id in GEAR_CACHE:
        return GEAR_CACHE[gear_id]
    
    url = f"https://www.strava.com/api/v3/gear/{gear_id}"
    headers = {"Authorization": f"Bearer {access_token}"}
    try:
        res = requests.get(url, headers=headers, timeout=5)
        if res.status_code == 200:
            gear_data = res.json()
            name = gear_data.get("name")
            GEAR_CACHE[gear_id] = name
            return name
    except Exception as e:
        print(f"⚠️ Warning: Could not fetch gear {gear_id}: {e}")
    return None


def get_location_info(lat, lng):
    if not lat or not lng:
        return {}
    
    key = (round(float(lat), 3), round(float(lng), 3))
    if key in GEO_CACHE:
        return GEO_CACHE[key]
    
    url = f"https://nominatim.openstreetmap.org/reverse?format=json&lat={lat}&lon={lng}"
    headers = {"User-Agent": "StravaFitnessAnalytics/1.0"}
    
    try:
        time.sleep(1)
        res = requests.get(url, headers=headers, timeout=5).json()
        address = res.get("address", {})
        
        info = {
            "City_District": address.get("city_district") or address.get("suburb") or address.get("neighbourhood"),
            "Village": address.get("village") or address.get("quarter"),
            "Town": address.get("town"),
            "City": address.get("city") or address.get("town") or address.get("municipality"),
            "Municipality": address.get("municipality") or address.get("city") or address.get("county"),
            "State": address.get("state") or address.get("region"),
            "Country": address.get("country")
        }
        GEO_CACHE[key] = info
        return info
    except Exception as e:
        print(f"⚠️ Warning: Could not geocode ({lat}, {lng}): {e}")
        return {}

# --- 1. LOAD ENVIRONMENT & CREDENTIALS ---
load_dotenv()
STRAVA_CLIENT_ID = os.getenv("STRAVA_CLIENT_ID")
STRAVA_CLIENT_SECRET = os.getenv("STRAVA_CLIENT_SECRET")
STRAVA_REFRESH_TOKEN = os.getenv("STRAVA_REFRESH_TOKEN")

def init_bigquery():
    """Initializes BigQuery client using local credentials.json if present, or ADC in Cloud Functions."""
    if os.path.exists('credentials.json'):
        creds = service_account.Credentials.from_service_account_file('credentials.json')
        proj_id = creds.project_id
        return bigquery.Client(credentials=creds, project=proj_id), proj_id
    else:
        proj_id = os.getenv("GCP_PROJECT_ID", "strava-sync-505308")
        return bigquery.Client(project=proj_id), proj_id

bq_client, PROJECT_ID = init_bigquery()
TABLE_ID = os.getenv("BIGQUERY_TABLE_ID", f"{PROJECT_ID}.strava_data.strava_activities")
SPLITS_TABLE_ID = os.getenv("BIGQUERY_SPLITS_TABLE_ID", f"{PROJECT_ID}.strava_data.strava_activity_splits")

def parse_activity_splits(activity_id, date_str, splits_metric):
    """Parses Strava splits_metric into structured split records for BigQuery."""
    if not splits_metric or not activity_id or not date_str:
        return []
    
    split_rows = []
    for split in splits_metric:
        dist_m = float(split.get("distance") or 0.0)
        dist_km = round(dist_m / 1000.0, 3)
        moving_sec = int(split.get("moving_time") or 0)
        elapsed_sec = int(split.get("elapsed_time") or 0)
        duration_min = round(moving_sec / 60.0, 2)
        
        pace_str = "N/A"
        pace_dec_min = None
        if dist_km > 0 and moving_sec > 0:
            pace_dec = (moving_sec / 60.0) / dist_km
            mins = int(pace_dec)
            secs = int(round((pace_dec - mins) * 60))
            if secs >= 60:
                mins += 1
                secs = 0
            pace_str = f"{mins:02d}:{secs:02d}/km"
            pace_dec_min = round(pace_dec, 2)
        
        avg_speed_ms = float(split.get("average_speed") or 0.0)
        avg_speed_kmh = round(avg_speed_ms * 3.6, 2) if avg_speed_ms > 0 else 0.0
        
        avg_gas = split.get("average_grade_adjusted_speed")
        avg_gas_kmh = round(float(avg_gas) * 3.6, 2) if avg_gas is not None and float(avg_gas) > 0 else None
        
        elev_diff = split.get("elevation_difference")
        elev_diff_m = round(float(elev_diff), 1) if elev_diff is not None else None
        
        avg_hr = split.get("average_heartrate")
        avg_hr_val = round(float(avg_hr), 1) if avg_hr is not None else None
        
        split_row = {
            "Strava_ID": int(activity_id),
            "Date": str(date_str),
            "Split_Num": int(split.get("split") or (len(split_rows) + 1)),
            "Distance_km": dist_km,
            "Duration_sec": moving_sec,
            "Elapsed_Time_sec": elapsed_sec,
            "Duration_min": duration_min,
            "Pace": pace_str,
            "Pace_Dec_Min": pace_dec_min,
            "Elevation_Diff_m": elev_diff_m,
            "Avg_HR": avg_hr_val,
            "Avg_Speed_kmh": avg_speed_kmh,
            "Avg_Grade_Adjusted_Speed_kmh": avg_gas_kmh,
            "Pace_Zone": int(split.get("pace_zone")) if split.get("pace_zone") is not None else None
        }
        split_rows.append(split_row)
    return split_rows

# --- 2. STRAVA FUNCTIONS ---
def get_strava_access_token():
    url = "https://www.strava.com/oauth/token"
    payload = {
        "client_id": STRAVA_CLIENT_ID,
        "client_secret": STRAVA_CLIENT_SECRET,
        "refresh_token": STRAVA_REFRESH_TOKEN,
        "grant_type": "refresh_token"
    }
    response = requests.post(url, data=payload)
    response.raise_for_status()
    return response.json()["access_token"]

def get_activities(access_token, start_timestamp=None, days=7):
    """
    Fetch activities from Strava with pagination.
    Defaults to fetching activities from the last 7 days.
    """
    url = "https://www.strava.com/api/v3/athlete/activities"
    headers = {"Authorization": f"Bearer {access_token}"}
    
    if days is not None:
        after_timestamp = int((datetime.now() - timedelta(days=days)).timestamp())
    elif start_timestamp is not None:
        after_timestamp = start_timestamp
    else:
        # Default: Jan 1st of the current year
        after_timestamp = int(datetime(datetime.now().year, 1, 1).timestamp())

    activities = []
    page = 1
    per_page = 200

    while True:
        params = {"after": after_timestamp, "per_page": per_page, "page": page}
        response = requests.get(url, headers=headers, params=params)
        response.raise_for_status()
        data = response.json()
        if not data:
            break
        activities.extend(data)
        if len(data) < per_page:
            break
        page += 1

    return activities

def get_recent_activities(access_token):
    return get_activities(access_token)

# --- 3. BIGQUERY FUNCTIONS ---
def get_existing_strava_ids():
    query = f"SELECT DISTINCT Strava_ID FROM `{TABLE_ID}`"
    query_job = bq_client.query(query)
    return {row.Strava_ID for row in query_job.result()}

def upload_to_bigquery(activities_to_upload, access_token=None):
    if not activities_to_upload:
        print("⏭️ No new activities to upload.")
        return

    # In-memory deduplication to ensure unique Strava IDs per batch
    seen_ids = set()
    unique_activities = []
    for act in activities_to_upload:
        act_id = act.get("id")
        if act_id and act_id not in seen_ids:
            seen_ids.add(act_id)
            unique_activities.append(act)

    rows_to_insert = []
    split_rows_to_insert = []
    headers = {"Authorization": f"Bearer {access_token}"} if access_token else None
    
    for activity in unique_activities:
        detailed_activity = None
        # Always fetch detailed activity if access_token is available to retrieve splits and full telemetry
        if access_token and activity.get("id"):
            try:
                detail_url = f"https://www.strava.com/api/v3/activities/{activity.get('id')}"
                res = requests.get(detail_url, headers=headers, timeout=10)
                if res.status_code == 200:
                    detailed_activity = res.json()
                    activity.update(detailed_activity)
            except Exception as e:
                print(f"⚠️ Warning: Could not fetch details for activity {activity.get('id')}: {e}")

        # Gear (Shoes/Equipment)
        gear_name = None
        if isinstance(activity.get("gear"), dict):
            gear_name = activity.get("gear", {}).get("name")
        gear_id = activity.get("gear_id")
        if not gear_name and gear_id and access_token:
            gear_name = get_gear_name(gear_id, access_token)

        # Start time & End time of activity & Date Breakdown
        start_date_local = activity.get("start_date_local", "")
        start_time_str = "N/A"
        end_time_str = "N/A"
        year_name = "N/A"
        day_name = "N/A"
        day_num = "N/A"
        month_name = "N/A"
        month_num = "N/A"
        week_num = "N/A"
        
        date_str = start_date_local.split("T")[0] if start_date_local else ""
        if date_str:
            try:
                dt = datetime.strptime(date_str, "%Y-%m-%d")
                year_name = dt.strftime("%Y")
                day_name = dt.strftime("%A")
                day_num = f"{dt.isoweekday():02d}"
                month_name = dt.strftime("%B")
                month_num = dt.strftime("%m")
                week_num = dt.strftime("%V")
            except Exception:
                pass

        if start_date_local:
            try:
                clean_iso = start_date_local.replace("Z", "").split("+")[0]
                start_dt = datetime.strptime(clean_iso, "%Y-%m-%dT%H:%M:%S")
                start_time_str = start_dt.strftime("%H:%M:%S")
                
                elapsed_secs = int(activity.get("elapsed_time", 0) or 0)
                end_dt = start_dt + timedelta(seconds=elapsed_secs)
                end_time_str = end_dt.strftime("%H:%M:%S")
            except Exception as e:
                print(f"⚠️ Warning: Could not parse timestamps from {start_date_local}: {e}")

        raw_distance_m = float(activity.get("distance", 0) or 0.0)
        raw_distance_km = raw_distance_m / 1000.0
        distance_km = round(raw_distance_km, 2)
        
        duration_min = activity.get("moving_time", 0) / 60.0
        elapsed_min = activity.get("elapsed_time", 0) / 60.0
        
        pace_str = "N/A"
        if distance_km > 0 and activity.get("type") == "Run":
            pace_dec = duration_min / distance_km
            mins = int(pace_dec)
            secs = int((pace_dec - mins) * 60)
            pace_str = f"{mins:02d}:{secs:02d}/km"
            
        activity_type = activity.get("type", "Workout")
        cadence_raw = activity.get("average_cadence")

        if cadence_raw and float(cadence_raw) > 0:
            cadence = float(cadence_raw)
            # Use duration_min (moving_time) so paused/standing time doesn't add phantom steps
            total_steps = int((cadence * 2) * duration_min)
        elif activity_type in ["Run", "Walk", "Hike"] and raw_distance_km > 0 and duration_min > 0:
            speed_kmh = raw_distance_km / (duration_min / 60.0)
            if activity_type in ["Walk", "Hike"]:
                total_steps = int(raw_distance_km * 1300)
            else:
                est_spm = max(145.0, min(180.0, 140.0 + 2.3 * speed_kmh))
                total_steps = int(est_spm * duration_min)
            cadence = round((total_steps / duration_min) / 2.0, 1)
        else:
            cadence = 0.0
            total_steps = 0

        avg_strides_min = int(math.ceil(cadence)) if cadence else 0
        avg_steps_min = int(math.ceil(total_steps / duration_min)) if (total_steps > 0 and duration_min > 0) else 0

        start_latlng = activity.get("start_latlng", []) or []
        start_lat = start_latlng[0] if len(start_latlng) > 0 else None
        start_lng = start_latlng[1] if len(start_latlng) > 1 else None
        loc_info = get_location_info(start_lat, start_lng) if (start_lat and start_lng) else {}
        
        row = {
            "Strava_ID": activity.get("id"),
            "Name": activity.get("name", "Workout"),
            "Date": date_str,
            "Year_Name": year_name,
            "Day_Name": day_name,
            "Day_Num": day_num,
            "Month_Name": month_name,
            "Month_Num": month_num,
            "Week_Num": week_num,
            "Type": activity.get("type", "Workout"),
            "Distance_km": distance_km,
            "Duration_min": round(duration_min, 1),
            "Elapsed_Time_min": round(elapsed_min, 1),
            "Elevation_m": round(activity.get("total_elevation_gain", 0), 1),
            "Pace": pace_str,
            "Gear": gear_name,
            "Start_Time": start_time_str,
            "End_Time": end_time_str,
            "Calories": float(activity.get("calories") or 0.0),
            "Avg_HR": float(activity.get("average_heartrate") or 0.0),
            "Cadence": cadence,
            "Total_Steps": total_steps,
            "Avg_Strides_Min": avg_strides_min,
            "Avg_Steps_Min": avg_steps_min,
            "Start_Lat": start_lat,
            "Start_Lng": start_lng,
            "City_District": loc_info.get("City_District"),
            "Village": loc_info.get("Village"),
            "Town": loc_info.get("Town"),
            "City": loc_info.get("City"),
            "Municipality": loc_info.get("Municipality"),
            "State": loc_info.get("State"),
            "Country": loc_info.get("Country")
        }
        rows_to_insert.append(row)

        # Parse splits if available in detailed activity
        if detailed_activity and detailed_activity.get("splits_metric") and date_str:
            splits = parse_activity_splits(activity.get("id"), date_str, detailed_activity.get("splits_metric"))
            split_rows_to_insert.extend(splits)

    # Pass row_ids to enforce BigQuery streaming buffer deduplication by unique Strava ID
    row_ids = [str(r["Strava_ID"]) for r in rows_to_insert]
    errors = bq_client.insert_rows_json(TABLE_ID, rows_to_insert, row_ids=row_ids)
    if errors:
        print(f"❌ Errors: {errors}")
    else:
        print(f"✅ Successfully loaded {len(rows_to_insert)} activities!")

    if split_rows_to_insert:
        split_row_ids = [f"{r['Strava_ID']}_{r['Split_Num']}" for r in split_rows_to_insert]
        split_errors = bq_client.insert_rows_json(SPLITS_TABLE_ID, split_rows_to_insert, row_ids=split_row_ids)
        if split_errors:
            print(f"❌ Splits Errors: {split_errors}")
        else:
            print(f"✅ Successfully loaded {len(split_rows_to_insert)} splits into `{SPLITS_TABLE_ID}`!")

# --- 4. EXECUTION ---
def run_sync():
    """Executes the Strava sync to BigQuery."""
    token = get_strava_access_token()
    print("🔄 Fetching Strava activities for the last 7 days...")
    recent_activities = get_activities(token, days=7)
    print(f"📊 Fetched {len(recent_activities)} total activities from Strava for the last 7 days.")
    
    existing_ids = get_existing_strava_ids()
    new_activities = [act for act in recent_activities if act.get("id") not in existing_ids]
    print(f"🆕 Found {len(new_activities)} new activities to sync into BigQuery.")
    
    upload_to_bigquery(new_activities, access_token=token)
    return {
        "status": "success",
        "fetched": len(recent_activities),
        "synced": len(new_activities)
    }

def sync_strava(request=None):
    """
    Google Cloud Functions entry point (HTTP trigger).
    Can also be called directly or scheduled via Cloud Scheduler.
    """
    try:
        result = run_sync()
        return (result, 200)
    except Exception as e:
        print(f"❌ Error during sync: {e}")
        return ({"status": "error", "error": str(e)}, 500)

if __name__ == "__main__":
    run_sync()