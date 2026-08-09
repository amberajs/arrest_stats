SELECT json_agg(t)
FROM (
  SELECT
    ENCODE(DIGEST(p.record_id::TEXT || 'secret_salt', 'sha256'), 'hex') AS hash_value,

    p.age AS age,

    p.sex AS sex,

    CASE
      WHEN COALESCE(p.race, '') IN ('OTHER', 'UNKNOWN', '') THEN 'OTHER/UNKNOWN'
      ELSE p.race
    END AS race,

    p.bmi_bin AS bmi_bin,

    p.days_served_bin AS days_served,

    p.has_exp_rel AS has_exp_rel,

  FROM pop_snap p

  ORDER BY hash_value ASC
) t;
