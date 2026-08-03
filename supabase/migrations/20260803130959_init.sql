CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_cron;

CREATE TABLE IF NOT EXISTS raw_payload_log (
    payload_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    inmate_id INTEGER NOT NULL,
    hash_value VARCHAR(64) NOT NULL UNIQUE,
    raw_json JSONB NOT NULL,
    ingested_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

CREATE TABLE IF NOT EXISTS agency_profiles (
    lookup_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    arrest_agency TEXT NOT NULL UNIQUE
);

INSERT INTO agency_profiles (lookup_id, arrest_agency)
OVERRIDING SYSTEM VALUE
VALUES (0, 'UNSPECIFIED')
ON CONFLICT (lookup_id) DO NOTHING;

CREATE TABLE IF NOT EXISTS officer_profiles (
    lookup_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    arresting_officer TEXT NOT NULL,
    agency_lookup_id BIGINT NOT NULL DEFAULT 0 REFERENCES agency_profiles(lookup_id),
    CONSTRAINT unique_officer_agency UNIQUE (arresting_officer, agency_lookup_id)
);

CREATE TABLE IF NOT EXISTS race_lookup (
    lookup_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    race TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS charge_lookup (
    lookup_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    charge_description TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS classification_lookup (
    lookup_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    classification TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS pod_lookup (
    lookup_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    pod TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS day_room_lookup (
    lookup_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    day_room TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS bed_lookup (
    lookup_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    bed TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS inmate_profiles (
    inmate_id INTEGER PRIMARY KEY,
    dob DATE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

CREATE TABLE IF NOT EXISTS inmate_names (
    name_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    inmate_id INTEGER NOT NULL REFERENCES inmate_profiles(inmate_id) ON DELETE CASCADE,
    first_name TEXT NOT NULL,
    middle_name TEXT,
    last_name TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_inmate_names_lookup ON inmate_names (last_name, first_name);

CREATE TABLE IF NOT EXISTS arrests (
    arrest_id INTEGER PRIMARY KEY,
    inmate_id INTEGER NOT NULL REFERENCES inmate_profiles(inmate_id) ON DELETE RESTRICT,
    payload_id BIGINT REFERENCES raw_payload_log(payload_id) ON DELETE SET NULL,

    booking_time TIMESTAMP WITH TIME ZONE,
    sex CHAR(1),
    height VARCHAR(10),
    weight VARCHAR(10),
    arresting_location TEXT,
    expected_release DATE,

    race_lookup_id BIGINT REFERENCES race_lookup(lookup_id),
    agency_lookup_id BIGINT REFERENCES agency_profiles(lookup_id),
    officer_lookup_id BIGINT REFERENCES officer_profiles(lookup_id),
    classification_lookup_id BIGINT REFERENCES classification_lookup(lookup_id),
    pod_lookup_id BIGINT REFERENCES pod_lookup(lookup_id),
    day_room_lookup_id BIGINT REFERENCES day_room_lookup(lookup_id),
    bed_lookup_id BIGINT REFERENCES bed_lookup(lookup_id),

    bitmask BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_arrests_inmate_id ON arrests (inmate_id);
CREATE INDEX IF NOT EXISTS idx_arrests_agency_id ON arrests (agency_lookup_id);
CREATE INDEX IF NOT EXISTS idx_arrests_officer_id ON arrests (officer_lookup_id);

CREATE TABLE IF NOT EXISTS arrest_charges (
    arrest_id INTEGER REFERENCES arrests(arrest_id) ON DELETE CASCADE,
    charge_id BIGINT REFERENCES charge_lookup(lookup_id) ON DELETE RESTRICT,
    CONSTRAINT pk_arrest_charges PRIMARY KEY (arrest_id, charge_id)
);

CREATE TABLE IF NOT EXISTS hash_log (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    arrest_id INTEGER REFERENCES arrests(arrest_id) ON DELETE CASCADE,
    hash_value VARCHAR(64) NOT NULL UNIQUE,
    source TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

CREATE TABLE IF NOT EXISTS bitmask_lookup (
    bit_value BIGINT PRIMARY KEY,
    column_name TEXT NOT NULL UNIQUE
);

INSERT INTO bitmask_lookup (bit_value, column_name) VALUES
(1, 'middle_name'),
(2, 'sex'),
(4, 'race'),
(8, 'height'),
(16, 'weight'),
(32, 'arresting_location'),
(64, 'arrest_agency'),
(128, 'arresting_officer'),
(256, 'classification'),
(512, 'charge_description'),
(1024, 'expected_release')
ON CONFLICT (bit_value) DO NOTHING;
