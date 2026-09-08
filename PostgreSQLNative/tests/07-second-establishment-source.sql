INSERT INTO core.establishment (
    urn, uid, name, establishment_type_id, establishment_status_id
)
SELECT
'POC100002', 'POC-UID-002', 'PoC Hilltop Primary School', e.establishment_type_id, e.establishment_status_id
FROM core.establishment AS e
WHERE e.urn = 'POC100001'
RETURNING establishment_id, urn, name;
