import hashlib
import json
import os
import random
import time
import re
from datetime import datetime
from dotenv import load_dotenv
import requests
import schedule
from supabase import Client, create_client

load_dotenv()
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("supabase_key")
RECENTS_API = os.getenv("RECENTS_API")
INMATE_BASE_API = os.getenv("INMATE_BASE_API")
USER_AGENT = os.getenv("USER_AGENT")
CONTACT_EMAIL = os.getenv("CONTACT_EMAIL")
PURPOSE = os.getenv("PURPOSE")

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

JAIL_HEADERS = {
    "Content-Type": "application/json",
    "User-Agent": USER_AGENT,
    "Contact-Email": CONTACT_EMAIL,
    "X-Purpose": PURPOSE,
}

FILENAME = "last_hash.txt"
last_time = None

def scrape_jail():
    """Fetches recent inmate list JSON from the jail API."""
    try:
        response = requests.get(url=RECENTS_API, headers=JAIL_HEADERS)
        response.raise_for_status()
        print("Received Jail JSON")
        return response.json()
    except requests.exceptions.HTTPError as http_err:
        print(f"HTTP error occurred: {http_err}")
    except requests.exceptions.JSONDecodeError:
        print("Error: The URL did not return valid JSON.")
    except Exception as err:
        print(f"An unexpected error occurred: {err}")
    return None

def generate_hash(data) -> str:
    """Generates a single SHA-256 hash from the combined batch JSON object."""
    payload_bytes = json.dumps(data, sort_keys=True).encode("utf-8")
    return hashlib.sha256(payload_bytes).hexdigest()

def get_last_hash(filename=FILENAME):
    """Reads previous hash from local file."""
    global last_time
    if os.path.exists(filename):
        with open(filename, "r") as f:
            time_raw = os.path.getmtime(filename)
            last_time = datetime.fromtimestamp(time_raw)
            return (f.read().strip())
    return ""

def save_success(new_hash, filename=FILENAME):
    """Saves the hash to file only after successful run."""
    with open(filename, "w") as f:
        f.write(new_hash)
    print(f"Saved new hash: {new_hash}")

def get_list(data):
    """Extracts inmate IDs from main jail payload."""
    if not data:
        return None
    return [inmate["inmateID"] for inmate in data if "inmateID" in inmate]

def scrape_inmate(inmate_id):
    """Fetches details for an individual inmate ID."""
    inmate_url = f"{INMATE_BASE_API}/{inmate_id}/"
    try:
        response = requests.get(url=inmate_url, headers=JAIL_HEADERS)
        response.raise_for_status()
        print(f"Received JSON for inmate {inmate_id}")
        time.sleep(random.uniform(2, 5))
        return response.json()
    except requests.exceptions.HTTPError as http_err:
        print(f"{inmate_id} HTTP error occurred: {http_err}")
    except requests.exceptions.JSONDecodeError:
        print(f"{inmate_id} Error: The URL did not return valid JSON.")
    except Exception as err:
        print(f"{inmate_id} An unexpected error occurred: {err}")
    return None

def filter_inmate(raw_data):
    if last_time is None:
        return True
    try:
        latest_label = None
        profile_images = raw_data.get("profileImages", [])
        if profile_images and isinstance(profile_images, list):
            latest_label = profile_images[0].get("label")
        if latest_label:
            dt_object = datetime.fromisoformat(latest_label)
            return dt_object > last_time
        booking_date_str = raw_data.get("inmate", {}).get("bookingDate")
        if booking_date_str:
            dt_object = datetime.strptime(booking_date_str, "%m/%d/%Y")
            return dt_object > last_time
        return True
    except Exception as e:
        return True

def run_all():
    """Main execution block."""
    data = scrape_jail()
    if not data:
        print("Error: Could not retrieve main jail payload.")
        return

    current_hash = generate_hash(data)
    last_hash = get_last_hash()

    if current_hash == last_hash:
        print("No data change. Exiting early.")
        return

    print("Getting inmate list.")

    inmate_list = get_list(data)
    if not inmate_list:
        print("No inmate IDs found in payload.")
        return

    records_to_upsert = []
    for inmate_id in inmate_list:
        raw_data = scrape_inmate(inmate_id)
        is_new = filter_inmate(raw_data)
        if is_new:
            print(f"New inmate:{inmate_id}")
            hash_val = generate_hash(raw_data)
            records_to_upsert.append(
                {
                    "inmate_id": inmate_id,
                    "raw_json": raw_data,
                    "hash_value": hash_val,
                }
            )

    if records_to_upsert:
        try:
            supabase.table("raw_payload_log").upsert(
                records_to_upsert,
                on_conflict="hash_value",
                ignore_duplicates=True,
            ).execute()
            print(f"Successfully upserted {len(records_to_upsert)} records.")

            save_success(current_hash)

        except Exception as e:
            print(f"Failed to upsert records into Supabase: {e}")
            print("Hash file NOT updated due to error.")


if __name__ == "__main__":
    run_all()
    # To run on schedule:
    # schedule.every().hour.do(run_all)
    # while True:
    #     schedule.run_pending()
    #     time.sleep(1)

