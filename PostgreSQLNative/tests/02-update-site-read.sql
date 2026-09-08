DO $$
BEGIN
    IF NOT EXISTS(SELECT 1
    FROM read_model.establishment
    WHERE urn = 'POC100001' AND (sites @> '[{"address_line_1":"25 Updated Road","postcode":"CF10 2BB"}]'::jsonb)) THEN
        RAISE EXCEPTION 'Expected result absent: wait for replication then retry this assertion';

    END IF;

END
$$;
