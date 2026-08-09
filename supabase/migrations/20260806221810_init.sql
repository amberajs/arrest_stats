CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS supabase_vault WITH SCHEMA vault;

CREATE TABLE IF NOT EXISTS raw_payload_log (
    payload_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    inmate_id INTEGER NOT NULL,
    hash_value VARCHAR(64) NOT NULL UNIQUE,
    raw_json JSONB NOT NULL,
    scraped_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

CREATE TABLE IF NOT EXISTS agency_profiles (
    lookup_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    arrest_agency TEXT NOT NULL UNIQUE
);

INSERT INTO agency_profiles (lookup_id, arrest_agency)
OVERRIDING SYSTEM VALUE
VALUES (0, 'UNSPECIFIED')
ON CONFLICT (arrest_agency) DO NOTHING;

CREATE TABLE IF NOT EXISTS officer_profiles (
    lookup_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    arresting_officer TEXT NOT NULL,
    agency_lookup_id BIGINT NOT NULL DEFAULT 0 REFERENCES agency_profiles(lookup_id),
    CONSTRAINT unique_officer_agency UNIQUE (arresting_officer, agency_lookup_id)
);

CREATE TABLE IF NOT EXISTS race_lookup (
    lookup_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    race_category VARCHAR(20) NOT NULL CHECK (race_category IN ('ASIAN', 'BLACK', 'HISPANIC', 'WHITE', 'OTHER', 'UNKNOWN')),
    race TEXT NOT NULL UNIQUE
);

INSERT INTO race_lookup (race_category, race) VALUES
('ASIAN', 'ASIAN'),
('BLACK', 'BLACK'),
('HISPANIC', 'HISPANIC'),
('WHITE', 'WHITE'),
('OTHER', 'OTHER'),
('UNKNOWN', 'UNKNOWN')
ON CONFLICT (race) DO NOTHING;

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

CREATE UNIQUE INDEX IF NOT EXISTS idx_inmate_names_unique_tuple
ON inmate_names (inmate_id, first_name, middle_name, last_name) NULLS NOT DISTINCT;

CREATE TABLE IF NOT EXISTS arrests (
    arrest_id INTEGER PRIMARY KEY,
    inmate_id INTEGER NOT NULL REFERENCES inmate_profiles(inmate_id) ON DELETE RESTRICT,
    payload_id BIGINT REFERENCES raw_payload_log(payload_id) ON DELETE RESTRICT,

    booking_time TIMESTAMP WITH TIME ZONE,
    dob DATE,
    age INTEGER GENERATED ALWAYS AS (
            (EXTRACT(YEAR FROM (booking_time AT TIME ZONE 'UTC')::date)::INTEGER - EXTRACT(YEAR FROM dob)::INTEGER) -
            CASE
                WHEN (
                    EXTRACT(MONTH FROM (booking_time AT TIME ZONE 'UTC')::date)::INTEGER < EXTRACT(MONTH FROM dob)::INTEGER
                    OR (
                        EXTRACT(MONTH FROM (booking_time AT TIME ZONE 'UTC')::date)::INTEGER = EXTRACT(MONTH FROM dob)::INTEGER
                        AND EXTRACT(DAY FROM (booking_time AT TIME ZONE 'UTC')::date)::INTEGER < EXTRACT(DAY FROM dob)::INTEGER
                     )
                ) THEN 1
                ELSE 0
            END
    ) STORED,
    sex TEXT,
    height INTEGER,
    weight INTEGER,
    arresting_location TEXT,
    expected_release DATE,

    race_lookup_id BIGINT REFERENCES race_lookup(lookup_id),
    agency_lookup_id BIGINT REFERENCES agency_profiles(lookup_id),
    officer_lookup_id BIGINT REFERENCES officer_profiles(lookup_id),
    classification_lookup_id BIGINT REFERENCES classification_lookup(lookup_id),
    pod_lookup_id BIGINT REFERENCES pod_lookup(lookup_id),
    day_room_lookup_id BIGINT REFERENCES day_room_lookup(lookup_id),
    bed_lookup_id BIGINT REFERENCES bed_lookup(lookup_id),

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

CREATE OR REPLACE FUNCTION trigger_process_raw_payload()
RETURNS TRIGGER AS $$
DECLARE
  edge_function_url TEXT;
  service_role_key TEXT;
  request_id BIGINT;
  payload JSONB;
BEGIN
  SELECT decrypted_secret INTO edge_function_url
  FROM vault.decrypted_secrets
  WHERE name = 'edge_function_url'
  LIMIT 1;

  SELECT decrypted_secret INTO service_role_key
  FROM vault.decrypted_secrets
  WHERE name = 'edge_function_service_key'
  LIMIT 1;

  IF edge_function_url IS NULL OR service_role_key IS NULL THEN
    RAISE EXCEPTION 'Missing vault secrets for edge function trigger.';
  END IF;

  payload := jsonb_build_object(
    'type', TG_OP,
    'table', TG_TABLE_NAME,
    'schema', TG_TABLE_SCHEMA,
    'record', to_jsonb(NEW)
  );

  SELECT net.http_post(
    url := edge_function_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || service_role_key
    ),
    body := payload
  ) INTO request_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_process_raw_payload ON raw_payload_log;

CREATE TRIGGER trg_process_raw_payload
AFTER INSERT ON raw_payload_log
FOR EACH ROW
EXECUTE FUNCTION trigger_process_raw_payload();

CREATE OR REPLACE FUNCTION process_arrest_payload(records_json JSONB)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    inserted_count INTEGER := 0;
BEGIN
    WITH parsed AS (
        SELECT
            payload_id,
            arrest_id,
            inmate_id,
            dob,
            booking_time,
            first_name,
            middle_name,
            last_name,
            sex,
            height,
            weight,
            arresting_location,
            UPPER(TRIM(race)) AS race,
            arrest_agency,
            arresting_officer
        FROM jsonb_to_recordset(records_json) AS x(
            payload_id BIGINT,
            arrest_id INTEGER,
            inmate_id INTEGER,
            dob DATE,
            booking_time TIMESTAMPTZ,
            first_name TEXT,
            middle_name TEXT,
            last_name TEXT,
            sex TEXT,
            height INTEGER,
            weight INTEGER,
            arresting_location TEXT,
            race TEXT,
            arrest_agency TEXT,
            arresting_officer TEXT
        )
        WHERE arrest_id IS NOT NULL AND inmate_id IS NOT NULL
    ),
    ins_agencies AS (
        INSERT INTO agency_profiles (arrest_agency)
        SELECT DISTINCT arrest_agency FROM parsed WHERE arrest_agency IS NOT NULL
        ON CONFLICT (arrest_agency) DO NOTHING
    ),
    ins_officers AS (
        INSERT INTO officer_profiles (arresting_officer, agency_lookup_id)
        SELECT DISTINCT
            p.arresting_officer,
            COALESCE(ap.lookup_id, 0)
        FROM parsed p
        LEFT JOIN agency_profiles ap ON ap.arrest_agency = p.arrest_agency
        WHERE p.arresting_officer IS NOT NULL
        ON CONFLICT (arresting_officer, agency_lookup_id) DO NOTHING
    ),
    ins_races AS (
        INSERT INTO race_lookup (race_category, race)
        SELECT DISTINCT
            CASE
                WHEN race IN ('ASIAN', 'BLACK', 'HISPANIC', 'WHITE', 'OTHER', 'UNKNOWN') THEN race
                ELSE 'OTHER'
            END AS race_category,
            race
        FROM parsed
        WHERE race IS NOT NULL AND race <> ''
        ON CONFLICT (race) DO NOTHING
    ),
    ins_profiles AS (
        INSERT INTO inmate_profiles (inmate_id, dob)
        SELECT DISTINCT inmate_id, dob FROM parsed WHERE dob IS NOT NULL
        ON CONFLICT (inmate_id) DO UPDATE SET created_at = inmate_profiles.created_at
        RETURNING inmate_id
    ),
    ins_names AS (
        INSERT INTO inmate_names (inmate_id, first_name, middle_name, last_name)
        SELECT DISTINCT p.inmate_id, p.first_name, p.middle_name, p.last_name 
        FROM parsed p
        JOIN ins_profiles ip ON ip.inmate_id = p.inmate_id
        WHERE p.first_name IS NOT NULL AND p.last_name IS NOT NULL
        ON CONFLICT (inmate_id, first_name, middle_name, last_name) DO NOTHING
    ),
    ins_arrests AS (
        INSERT INTO arrests (
            arrest_id, inmate_id, payload_id, booking_time, dob, sex, height, weight,
            arresting_location, agency_lookup_id, officer_lookup_id, race_lookup_id
        )
        SELECT
            p.arrest_id,
            p.inmate_id,
            p.payload_id,
            p.booking_time,
            p.dob,
            p.sex,
            p.height,
            p.weight,
            p.arresting_location,
            ap.lookup_id,
            op.lookup_id,
            rl.lookup_id
        FROM parsed p
        JOIN ins_profiles ip ON ip.inmate_id = p.inmate_id
        LEFT JOIN agency_profiles ap ON ap.arrest_agency = p.arrest_agency
        LEFT JOIN officer_profiles op ON op.arresting_officer = p.arresting_officer 
            AND op.agency_lookup_id = COALESCE(ap.lookup_id, 0)
        LEFT JOIN race_lookup rl ON rl.race = p.race
        ON CONFLICT (arrest_id) DO UPDATE SET
            payload_id = EXCLUDED.payload_id,
            booking_time = COALESCE(EXCLUDED.booking_time, arrests.booking_time),
            arresting_location = COALESCE(EXCLUDED.arresting_location, arrests.arresting_location),
            agency_lookup_id = COALESCE(EXCLUDED.agency_lookup_id, arrests.agency_lookup_id),
            officer_lookup_id = COALESCE(EXCLUDED.officer_lookup_id, arrests.officer_lookup_id),
            race_lookup_id = COALESCE(EXCLUDED.race_lookup_id, arrests.race_lookup_id)
        RETURNING 1
    )
    SELECT COUNT(*) INTO inserted_count FROM ins_arrests;

    RETURN inserted_count;
END;
$$;

GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA public TO service_role;
