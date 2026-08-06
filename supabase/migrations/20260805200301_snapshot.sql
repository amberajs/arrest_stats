DROP TABLE IF EXISTS raw_pop CASCADE;
DROP TABLE IF EXISTS pop_snap CASCADE;

CREATE TABLE IF NOT EXISTS raw_pop (
    payload_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    inmate_id_starts INTEGER NOT NULL,
    hash_value VARCHAR(64) NOT NULL,
    raw_json JSONB NOT NULL,
    scraped_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

CREATE TABLE IF NOT EXISTS pop_snap (
    record_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    age INTEGER,
    sex TEXT,
    race TEXT,
    bmi INTEGER,
    days_served INTEGER,
    days_left INTEGER,
    hash_value VARCHAR(64)
);
CREATE OR REPLACE FUNCTION process_json_array(p_payload_id BIGINT)
RETURNS INTEGER AS $$
DECLARE
    v_rows_inserted INTEGER;
BEGIN
    INSERT INTO pop_snap (
        age,
        sex,
        race,
        bmi,
        days_served,
        days_left,
        hash_value
    )
    SELECT
        -- age = booking_date - dob (in years)
        EXTRACT(YEAR FROM AGE(
            TO_DATE(substring(j.image FROM '(?i)_(\d{8})\d{6}\.jpg$'), 'MMDDYYYY')::TIMESTAMP,
            TO_DATE(j.dob, 'MM/DD/YYYY')::TIMESTAMP
        ))::INTEGER AS age,

        -- sex and race to uppercase
        UPPER(j.sex) AS sex,
        UPPER(j.race) AS race,

        -- BMI rounded to nearest integer
        ROUND(
            (703.0 * NULLIF(j.weight, 0) / NULLIF(j.height ^ 2, 0))::numeric,
            0
        )::INTEGER AS bmi,

        -- days_served = scraped_at (in UTC date) - booking_date
        (
            (s.scraped_at AT TIME ZONE 'UTC')::date -
            TO_DATE(substring(j.image FROM '(?i)_(\d{8})\d{6}\.jpg$'), 'MMDDYYYY')
        ) AS days_served,

        -- days_left = expected_release - scraped_at (in UTC date)
        (
            TO_DATE(j.expected_release, 'MM/DD/YYYY') -
            (s.scraped_at AT TIME ZONE 'UTC')::date
        ) AS days_left,

        -- hash value from source table
        s.hash_value

    FROM raw_pop s
    CROSS JOIN LATERAL jsonb_to_recordset(s.raw_json) AS j(
        image TEXT,
        dob TEXT,
        sex TEXT,
        race TEXT,
        height NUMERIC,
        weight NUMERIC,
        expected_release TEXT
    )
    WHERE s.payload_id = p_payload_id;

    GET DIAGNOSTICS v_rows_inserted = ROW_COUNT;
    RETURN v_rows_inserted;
END;
$$ LANGUAGE plpgsql;

-- search path
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

-- permissions
GRANT SELECT, INSERT, UPDATE ON public.raw_pop TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.pop_snap TO service_role;
GRANT EXECUTE ON FUNCTION process_json_array(BIGINT) TO service_role;
GRANT EXECUTE ON FUNCTION process_json_array_batch(BIGINT[]) TO service_role;
