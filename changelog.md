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

## 2026-08-05

### Added
- new migrations init to fix missing arrest_agency column and ctx arrest_agency issue
- new migrations snapshot to collect current inmate snapshot
- new migrations snapshot to remove identifying columns
- new migrations snapshot to fix days_left calculation
- new other_scraper.py to scrape snapshot data
- new data_validation.md to audit/troubleshoot data integrity issues

### Changed
- READ.ME to update changes to original design including addition of snapshot
- scraper.py changed MD5 hash to SHA-256

## 2026-08-06

### Added
- new migrations init to insert table values for race_lookup
- new migrations snapshot to create relation with race_lookup table
- new migrations init fixed race_lookup bug from previous add
- new migrations snapshot fixed race_lookup bug from previous add

### Changed
- data_validation.md documented data transformation methods and results

### 2026-08-09

### Added
- new migrations init fixed race_lookup bug from previous add
- new migrations snapshot fixed race_lookup bug from previous add
- data directory for json_agg.sql (export and format static data), jail_snapshot.json (static data file), data_sources.md (population data and sources for snapshot), original sources directory (5 sources)

### Moved
- data_validation.md to new data directory

## 2026-08-09

### Changed
- READ.ME updates on previous push
