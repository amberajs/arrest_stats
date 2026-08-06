import hashlib
import json
import os
import random
import time
from dotenv import load_dotenv
import requests
from supabase import Client, create_client

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("supabase_key")
SEARCH_BASE_API = os.getenv("SEARCH_BASE_API")
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

NUM_LIST = list(range(3, 30))


def scrape_search(session: requests.Session, num: int):
    """Fetches raw JSON payload for a given inmate search number using a shared session."""
    try:
        url = f"{SEARCH_BASE_API}{num}"
        response = session.get(url, headers=JAIL_HEADERS, timeout=15)
        response.raise_for_status()
        print(f"Received Jail JSON for search of {num}")
        return response.json()
    except requests.RequestException as err:
        print(f"Error scraping search prefix {num}: {err}")
    return None


def generate_batch_hash(batch_data: list) -> str:
    """Generates a single SHA-256 hash from the combined batch JSON object."""
    payload_bytes = json.dumps(batch_data, sort_keys=True).encode("utf-8")
    return hashlib.sha256(payload_bytes).hexdigest()


def run_all():
    scraped_batch = []

    with requests.Session() as session:
        for num in NUM_LIST:
            raw_data = scrape_search(session, num)
            if raw_data:
                scraped_batch.append({
                    "inmate_id_starts": num,
                    "raw_json": raw_data
                })
            time.sleep(random.uniform(1.0, 2.0))

    if not scraped_batch:
        print("No valid data collected.")
        return

    batch_hash = generate_batch_hash(scraped_batch)
    print(f"Batch Hash: {batch_hash}")

    records_to_insert = [
        {
            "inmate_id_starts": item["inmate_id_starts"],
            "raw_json": item["raw_json"],
            "hash_value": batch_hash
        }
        for item in scraped_batch
    ]

    try:
        response = (
            supabase.table("raw_pop")
            .insert(records_to_insert)
            .execute()
        )
        print(f"Successfully upserted batch of {len(records_to_insert)} records.")


        if response.data:
            payload_ids = [
                record["payload_id"]
                for record in response.data
                if record.get("payload_id") is not None
            ]

            if payload_ids:
                supabase.rpc(
                    "process_json_array_batch",
                    {"p_payload_ids": payload_ids}
                ).execute()
                print(f"Batch processed {len(payload_ids)} payload IDs successfully.")

    except Exception as e:
        print(f"Failed to upsert or process batch: {e}")


if __name__ == "__main__":
    run_all()
