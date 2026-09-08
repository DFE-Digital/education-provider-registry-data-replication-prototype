DO $$
BEGIN
    IF NOT EXISTS (SELECT 1
        FROM read_model.establishment
        WHERE urn = 'POC100001'
        AND name = 'PoC Riverside Primary School' AND establishment_status_name = 'Open'
        AND education_phase_name = 'Primary' AND jsonb_array_length(sites)=1 AND jsonb_array_length(authorities)=1)
    THEN
        RAISE EXCEPTION 'Baseline missing or incorrect';

    END IF;

END
$$;
