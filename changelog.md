changelog

## 2026-08-03

### Added
- new migrations init to include inmate_id column to match scraper.py functionality
- new migrations init to give service_role permission to scraper.py

### Changed
- scraper.py to use hash checks before database bulk insert to raw_payload_log


## 2026-08-04

### Added
- new migrations init with database triggers for format_data edge function on every new row in raw_payload_log
- new migrations init with rpc for format_data table inserts, also removed bitmask logic

### Changed
- requirements.txt to reflect previous changes to scraper.py
- format_data/index.ts to format raw json from raw_payload_log table and insert to arrests table
- config.toml to remove old edge function names and replace with format_data
- scraper.py to filter pre-existing arrests before upsert

