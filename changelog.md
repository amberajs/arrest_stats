changelog

## 2026-08-03

### Added
- new migrations init to include inmate_id column to match scraper.py functionality
- new migrations init to give service_role permission to scraper.py

### Changed
- scraper.py to use hash checks before database bulk insert to raw_payload_log
- last_hash.txt (from scraper.py changes) now listed on .gitignore
