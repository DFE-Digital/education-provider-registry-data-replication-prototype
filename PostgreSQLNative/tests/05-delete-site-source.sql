DELETE
FROM core.site
WHERE name = 'PoC Additional Site'
AND establishment_id = (
    SELECT establishment_id
    FROM core.establishment
    WHERE urn = 'POC100001'
)
RETURNING site_id, name;
