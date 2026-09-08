BEGIN;

UPDATE ref.establishment_status SET name = 'PoC Open Updated'
WHERE code = 'POC_OPEN';

UPDATE ref.education_phase SET name = 'PoC Primary Updated'
WHERE code = 'POC_PRIMARY';

INSERT INTO core.establishment_provision(establishment_id, education_phase_id)
SELECT e.establishment_id, p.education_phase_id
FROM core.establishment e
CROSS JOIN ref.education_phase p
WHERE e.urn = 'POC100002' AND p.code = 'POC_PRIMARY';

UPDATE core.site SET establishment_id=(SELECT establishment_id
    FROM core.establishment
    WHERE urn = 'POC100002')
WHERE name = 'Main Site' AND establishment_id=(SELECT establishment_id
    FROM core.establishment
    WHERE urn = 'POC100001');

COMMIT;
