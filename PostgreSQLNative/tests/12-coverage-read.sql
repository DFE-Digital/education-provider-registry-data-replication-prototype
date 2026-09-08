DO $$
BEGIN
    IF (SELECT count(*)
        FROM read_model.establishment
        WHERE urn IN ('POC100001', 'POC100002')
        AND establishment_status_name = 'PoC Open Updated' AND education_phase_name = 'PoC Primary Updated')<>2
    OR NOT EXISTS(SELECT 1
        FROM read_model.establishment
        WHERE urn = 'POC100001' AND sites = '[]'::jsonb)
    OR NOT EXISTS(SELECT 1
        FROM read_model.establishment
        WHERE urn = 'POC100002' AND jsonb_array_length(sites)=1)
    THEN
        RAISE EXCEPTION 'Coverage result absent; wait for replication and retry';

    END IF;

END
$$;
