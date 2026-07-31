import os
import sys
import time
import json
import random
import hashlib
import requests
from supabase import create_client, Client

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_KEY = os.environ.get("supabase_key", "")
RECENTS_API = os.environ.get("RECENTS_API", "")
INMATE_BASE_API = os.environ.get("INMATE_BASE_API", "")
USER_AGENT = os.environ.get("USER_AGENT", "")
CONTACT_EMAIL = os.environ.get("CONTACT_EMAIL", "")
PURPOSE = os.environ.get("PURPOSE", "")

if not SUPABASE_URL or not SUPABASE_KEY:
    sys.exit(1)

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

def get_headers():
    return {
        "User-Agent": USER_AGENT,
        "From": CONTACT_EMAIL,
        "X-Purpose": PURPOSE,
        "Content-Type": "application/json"
    }

def fetch_json(url):
    try:
        res = requests.get(url, headers=get_headers(), timeout=15)
        if res.status_code == 200:
            return res.text
        return None
    except Exception:
        return None

def is_paused():
    try:
        res = supabase.rpc("is_scraper_paused", {}).execute()
        return res.data is True
    except Exception:
        return False

def scrape_recents():
    raw_text = fetch_json(RECENTS_API)
    if not raw_text:
        return
    payload_hash = hashlib.sha256(raw_text.encode("utf-8")).hexdigest()
    try:
        data = json.loads(raw_text)
        payload = {"response": data, "hash": payload_hash}
        edge_url = f"{SUPABASE_URL}/functions/v1/jail_parser"
        headers = {"Authorization": f"Bearer {SUPABASE_KEY}", "Content-Type": "application/json"}
        requests.post(edge_url, json=payload, headers=headers, timeout=15)
    except Exception:
        pass

def process_queue():
    if is_paused():
        time.sleep(900)
        return

    try:
        res = supabase.from_("queue").select("inmate_id, url").order("id", desc=False).limit(1).execute()
        if not res.data or len(res.data) == 0:
            time.sleep(10)
            return

        item = res.data[0]
        inmate_id = item["inmate_id"]
        target_url = item["url"] or f"{INMATE_BASE_API}{inmate_id}/"

        raw_text = fetch_json(target_url)
        if not raw_text:
            time.sleep(10)
            return

        payload_hash = hashlib.sha256(raw_text.encode("utf-8")).hexdigest()
        data = json.loads(raw_text)
        payload = {"inmate_id": inmate_id, "data": data, "hash": payload_hash}

        edge_url = f"{SUPABASE_URL}/functions/v1/inmate_parser"
        headers = {"Authorization": f"Bearer {SUPABASE_KEY}", "Content-Type": "application/json"}
        requests.post(edge_url, json=payload, headers=headers, timeout=15)

        time.sleep(random.uniform(2.0, 6.0))

    except Exception:
        time.sleep(10)

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--recents":
        scrape_recents()
    else:
        while True:
            process_queue()
