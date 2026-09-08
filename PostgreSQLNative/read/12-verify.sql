SELECT
    urn,
    name,
    establishment_type_name,
    establishment_status_name,
    education_phase_name,
    jsonb_array_length(sites) AS site_count,
    jsonb_pretty(sites) AS sites,
    jsonb_pretty(authorities) AS authorities
FROM read_model.establishment
ORDER BY urn;

SELECT tgrelid::regclass, tgname, tgenabled
FROM pg_trigger
WHERE NOT tgisinternal AND tgfoid IN (SELECT oid
    FROM pg_proc
    WHERE pronamespace = 'read_model'::regnamespace)
ORDER BY 1, 2;

SELECT e.establishment_id AS raw_id, r.establishment_id AS projected_id
FROM core.establishment e
FULL
JOIN read_model.establishment r USING(establishment_id)
WHERE e.establishment_id IS NULL OR r.establishment_id IS NULL;
