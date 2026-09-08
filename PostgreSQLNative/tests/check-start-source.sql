DO $$
BEGIN
    IF (SELECT count(*) FROM core.establishment) <> 1
        OR NOT EXISTS (
            SELECT 1
            FROM core.establishment
            WHERE urn = 'POC100001'
        )
        OR (SELECT count(*) FROM core.site) <> 1
        OR NOT EXISTS (
            SELECT 1
            FROM core.site
            WHERE name = 'Main Site'
                AND address_line_1 = '1 Example Road'
        )
    THEN
        RAISE EXCEPTION 'Tests need the original sample data. A test has already run or the data has changed.';
    END IF;
END
$$;
