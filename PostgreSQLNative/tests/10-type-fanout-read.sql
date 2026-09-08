DO $$
BEGIN
    IF NOT EXISTS(SELECT 1
    FROM read_model.establishment
    WHERE urn = 'POC100001' AND ((SELECT count(*)
            FROM read_model.establishment
            WHERE urn IN ('POC100001', 'POC100002') AND establishment_type_name = 'PoC Community Primary School - Updated')=2)) THEN
        RAISE EXCEPTION 'Expected result absent: wait for replication then retry this assertion';

    END IF;

END
$$;
