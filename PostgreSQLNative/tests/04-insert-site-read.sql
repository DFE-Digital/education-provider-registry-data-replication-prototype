DO $$
BEGIN
    IF NOT EXISTS(SELECT 1
    FROM read_model.establishment
    WHERE urn = 'POC100001' AND (jsonb_array_length(sites)=2)) THEN
        RAISE EXCEPTION 'Expected result absent: wait for replication then retry this assertion';

    END IF;

END
$$;
