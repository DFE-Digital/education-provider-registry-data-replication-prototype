UPDATE core.site
SET
address_line_1 = '25 Updated Road', postcode = 'CF10 2BB'
WHERE establishment_id = (
    SELECT establishment_id
    FROM core.establishment
    WHERE urn = 'POC100001'
);
