INSERT INTO core.site (
    establishment_id, name, address_line_1, town, county, postcode
)
SELECT
e.establishment_id, 'PoC Additional Site', '10 Test Lane', 'Cardiff', 'South Glamorgan', 'CF11 9ZZ'
FROM core.establishment AS e
WHERE e.urn = 'POC100001'
RETURNING site_id, establishment_id, name;
