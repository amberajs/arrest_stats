import hashlib
import json
import os
import time
import requests
from dotenv import load_dotenv
import schedule

# Env variables
load_dotenv()
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("supabase_key")
RECENTS_API = os.getenv("RECENTS_API")
USER_AGENT = os.getenv("USER_AGENT")
CONTACT_EMAIL = os.getenv("CONTACT_EMAIL")
PURPOSE = os.getenv("PURPOSE")

# Headers
SUPABASE_HEADERS = {
    "Content-Type": "application/json",
    "apikey": SUPABASE_KEY,
    "Authorization": f"Bearer {SUPABASE_KEY}",
}

JAIL_HEADERS = {
    "Content-Type": "application/json",
    "User-Agent": USER_AGENT,
    "Contact-Email": CONTACT_EMAIL,
    "X-Purpose": PURPOSE,
}

# Global holders
DATA = None
HASH = None

def scrape_jail():
  global DATA
  try:
    response = requests.get(url=RECENTS_API, headers=JAIL_HEADERS)
    response.raise_for_status()
    DATA = response.json()
    print("Received JSON")
  except requests.exceptions.HTTPError as http_err:
    print(f"HTTP error occurred: {http_err}")
  except requests.exceptions.JSONDecodeError:
    print("Error: The URL did not return valid JSON.")
  except Exception as err:
    print(f"An unexpected error occurred: {err}")

def generate_hash():
  global HASH, DATA
  if DATA is None:
    print("Error: No data to hash.")
    return
  PAYLOAD_BYTES = json.dumps(DATA, sort_keys=True).encode("utf-8")
  HASH = hashlib.sha256(PAYLOAD_BYTES).hexdigest()
  print(f"Hash: {HASH}")

def to_jail_parser():
  global DATA, HASH
  if DATA is None or HASH is None:
    print("Error: Missing data or hash for parser.")
    return
  URL = f"{SUPABASE_URL}/functions/v1/jail_parser"
  BODY = {"data": DATA, "hash": HASH}
  try:
    response = requests.post(URL, json=BODY, headers=SUPABASE_HEADERS)
    if response.status_code == 200:
      print("Received by edge function: ", response.json())
    else:
      print(f"Error {response.status_code}: {response.text}")
  except Exception as err:
    print(f"Request failed: {err}")

def run_all():
  scrape_jail()
  if DATA:
    generate_hash()
    to_jail_parser()
  print("Complete")

if __name__ == "__main__":
    run_all()

# schedule.every().hour.do(run_all)
# while True:
#     schedule.run_pending()
#     time.sleep(1)
