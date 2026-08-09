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

DROP TABLE IF EXISTS pop_snap CASCADE;

CREATE TABLE IF NOT EXISTS pop_snap (
    record_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    age INTEGER,
    sex TEXT,
    race TEXT,
    bmi NUMERIC,
    bmi_bin TEXT GENERATED ALWAYS AS (
    CASE
        WHEN bmi <= 18.5 THEN 'UNDERWEIGHT'
        WHEN bmi BETWEEN 18.5 AND 24.9 THEN 'NORMAL'
        WHEN bmi BETWEEN 25 AND 29.9 THEN 'OVERWEIGHT'
        WHEN bmi >= 30 THEN 'OBESE'
        ELSE 'UNDEFINED'
    END
    ) STORED,
    days_served INTEGER,
    days_served_bin TEXT GENERATED ALWAYS AS (
        CASE
        WHEN days_served <= 2                THEN '0-2 DAYS'
        WHEN days_served BETWEEN 3 AND 7     THEN '3-7 DAYS'
        WHEN days_served BETWEEN 8 AND 30    THEN '8-30 DAYS'
        WHEN days_served BETWEEN 31 AND 180  THEN '31-180 DAYS'
        WHEN days_served BETWEEN 181 AND 364 THEN '181-364 DAYS'
        WHEN days_served >= 365              THEN '1+ YEARS'
        ELSE 'Uncategorized'
    END
   ) STORED,
   days_left INTEGER,
   has_exp_rel TEXT GENERATED ALWAYS AS (
        CASE
        WHEN days_left IS NOT NULL THEN 'YES'
        ELSE 'NO'
    END
  ) STORED,
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
        EXTRACT(YEAR FROM AGE(
            TO_DATE(substring(j.image FROM '(?i)_(\d{8})\d{6}\.jpg$'), 'MMDDYYYY')::TIMESTAMP,
            (CASE
                WHEN j.dob ~ '^\d{4}-\d{2}-\d{2}' THEN j.dob::date
                WHEN j.dob ~ '^\d{1,2}/\d{1,2}/\d{4}' THEN TO_DATE(j.dob, 'MM/DD/YYYY')
                ELSE NULL
            END)::TIMESTAMP
        ))::INTEGER AS age,

        UPPER(j.sex) AS sex,

        UPPER(j.race) AS race,

        ROUND(
            (703.0 * NULLIF(j.weight, 0) / NULLIF(j.height ^ 2, 0))::numeric,
            1
        )::NUMERIC AS bmi,

        (
            (s.scraped_at AT TIME ZONE 'UTC')::date -
            TO_DATE(substring(j.image FROM '(?i)_(\d{8})\d{6}\.jpg$'), 'MMDDYYYY')
        ) AS days_served,

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

GRANT SELECT, INSERT, UPDATE ON public.raw_pop TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.pop_snap TO service_role;
GRANT EXECUTE ON FUNCTION process_json_array(BIGINT) TO service_role;
GRANT EXECUTE ON FUNCTION process_json_array_batch(BIGINT[]) TO service_role;
