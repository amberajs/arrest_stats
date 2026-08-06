CREATE TABLE IF NOT EXISTS raw_pop (
    payload_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    inmate_id_starts INTEGER NOT NULL,
    hash_value VARCHAR(64) NOT NULL,
    raw_json JSONB NOT NULL,
    scraped_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

CREATE OR REPLACE RULE no_delete_raw_data AS
ON DELETE TO raw_pop
DO INSTEAD NOTHING;

DROP TABLE IF EXISTS bmi_lookup CASCADE;

CREATE TABLE IF NOT EXISTS bmi_lookup (
    id SERIAL PRIMARY KEY,
    category VARCHAR(20) NOT NULL CHECK (category IN ('UNDERWEIGHT', 'NORMAL', 'OVERWEIGHT', 'OBESE')),
    min_bmi NUMERIC(4, 1) NOT NULL
);

INSERT INTO bmi_lookup (category, min_bmi) VALUES
('UNDERWEIGHT', 0.0),
('NORMAL', 18.5),
('OVERWEIGHT', 25.0),
('OBESE', 30.0);

DROP TABLE IF EXISTS days_served_bins CASCADE;

CREATE TABLE IF NOT EXISTS days_served_bins (
    id SERIAL PRIMARY KEY,
    category VARCHAR(20) NOT NULL CHECK (category IN ('2', '7', '30', '180', '365', 'YEAR_PLUS')),
    min_days_served NUMERIC(6, 1) NOT NULL
);

INSERT INTO days_served_bins (category, min_days_served) VALUES
('2', 0),
('7', 7),
('30', 30),
('180', 180),
('365', 365),
('YEAR_PLUS', 366);

DROP TABLE IF EXISTS pop_snap CASCADE;

CREATE TABLE IF NOT EXISTS pop_snap (
    record_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    age INTEGER,
    sex TEXT,
    race_lookup_id BIGINT REFERENCES race_lookup(lookup_id),
    bmi_lookup_id BIGINT REFERENCES bmi_lookup(id),
    days_served INTEGER,
    days_served_id BIGINT REFERENCES days_served_bins(id),
    days_left INTEGER,
    hash_value VARCHAR(64)
);

CREATE OR REPLACE FUNCTION process_json_array(p_payload_id BIGINT)
RETURNS INTEGER AS $$
DECLARE
    v_rows_inserted INTEGER;
BEGIN

    INSERT INTO race_lookup (race_category, race)
    SELECT DISTINCT
        UPPER(j.race) AS race_category,
        UPPER(j.race) AS race
    FROM raw_pop s
    CROSS JOIN LATERAL jsonb_to_recordset(s.raw_json) AS j(race TEXT)
    WHERE s.payload_id = p_payload_id
        AND j.race IS NOT NULL
        AND TRIM(j.race) <> ''
    ON CONFLICT (race) DO NOTHING;

    INSERT INTO pop_snap (
        age,
        sex,
        race_lookup_id,
        bmi_lookup_id,
        days_served,
        days_served_id,
        days_left,
        hash_value
    )
    SELECT
        EXTRACT(YEAR FROM AGE(
            TO_DATE(substring(j.image FROM '(?i)_(\d{8})\d{6}\.jpg$'), 'MMDDYYYY')::TIMESTAMP,
            (CASE
                WHEN j.dob ~ '^\d{4}-\d{2}-\d{2}' THEN j.dob::date
                WHEN j.dob ~ '^\d{1,2}/\d{1,2}/\d{4}' THEN TO_DATE(j.dob, 'MM/DD/YYYY')
                ELSE NULL
            END)::TIMESTAMP
        ))::INTEGER AS age,

        UPPER(j.sex) AS sex,

        rl.lookup_id AS race_lookup_id,

        (
            SELECT b.id
            FROM bmi_lookup b
            WHERE b.min_bmi <= calc.bmi_val
            ORDER BY b.min_bmi DESC
            LIMIT 1
        ) AS bmi_lookup_id,

        calc.days_served,

        (
            SELECT d.id
            FROM days_served_bins d
            WHERE d.min_days_served <= calc.days_served
            ORDER BY d.min_days_served DESC
            LIMIT 1
        ) AS days_served_id,

        (
            CASE
                WHEN j."expectedRelease" ~ '^\d{4}-\d{2}-\d{2}' THEN j."expectedRelease"::date
                WHEN j."expectedRelease" ~ '^\d{1,2}/\d{1,2}/\d{4}' THEN TO_DATE(j."expectedRelease", 'MM/DD/YYYY')
                ELSE NULL
            END - (s.scraped_at AT TIME ZONE 'UTC')::date
        ) AS days_left,

        s.hash_value
    FROM raw_pop s
    CROSS JOIN LATERAL jsonb_to_recordset(s.raw_json) AS j(
        image TEXT,
        dob TEXT,
        sex TEXT,
        race TEXT,
        height NUMERIC,
        weight NUMERIC,
        "expectedRelease" TEXT
    )
    LEFT JOIN race_lookup rl ON rl.race = UPPER(j.race)
    CROSS JOIN LATERAL (
        SELECT
            ROUND(
                (703.0 * NULLIF(j.weight, 0) / NULLIF(j.height ^ 2, 0))::numeric,
                1
            ) AS bmi_val,
            (
                (s.scraped_at AT TIME ZONE 'UTC')::date -
                TO_DATE(substring(j.image FROM '(?i)_(\d{8})\d{6}\.jpg$'), 'MMDDYYYY')
            ) AS days_served
    ) calc
    WHERE s.payload_id = p_payload_id;

    GET DIAGNOSTICS v_rows_inserted = ROW_COUNT;
    RETURN v_rows_inserted;
END;
$$ LANGUAGE plpgsql;


ALTER FUNCTION process_json_array(BIGINT) SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION process_json_array_batch(p_payload_ids BIGINT[])
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_id BIGINT;
BEGIN
    FOREACH v_id IN ARRAY p_payload_ids
    LOOP
        PERFORM process_json_array(v_id);
    END LOOP;
END;
$$;

ALTER FUNCTION process_json_array_batch(BIGINT[]) SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION trg_process_raw_pop()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM process_json_array(NEW.payload_id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_auto_process_pop_snap ON raw_pop;

CREATE TRIGGER trg_auto_process_pop_snap
AFTER INSERT ON raw_pop
FOR EACH ROW
EXECUTE FUNCTION trg_process_raw_pop();

-- Permissions
GRANT SELECT, INSERT, UPDATE ON public.raw_pop TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.pop_snap TO service_role;
GRANT SELECT ON public.bmi_lookup TO service_role;
GRANT SELECT ON public.days_served_bins TO service_role;
GRANT EXECUTE ON FUNCTION process_json_array(BIGINT) TO service_role;
GRANT EXECUTE ON FUNCTION process_json_array_batch(BIGINT[]) TO service_role;
