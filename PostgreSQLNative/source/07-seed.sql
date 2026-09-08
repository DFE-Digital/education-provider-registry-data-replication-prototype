BEGIN;

INSERT INTO ref.establishment_family(code, name) VALUES ('POC_FAMILY', 'PoC Schools');

INSERT INTO ref.establishment_type(establishment_family_id, code, name, is_school)
SELECT establishment_family_id, 'POC_TYPE', 'PoC Community School', true
FROM ref.establishment_family
WHERE code = 'POC_FAMILY';

INSERT INTO ref.establishment_status(code, name) VALUES ('POC_OPEN', 'Open');

INSERT INTO ref.education_phase_group(code, name) VALUES ('POC_PHASE_GROUP', 'PoC School phases');

INSERT INTO ref.education_phase(education_phase_group_id, code, name)
SELECT education_phase_group_id, 'POC_PRIMARY', 'Primary'
FROM ref.education_phase_group
WHERE code = 'POC_PHASE_GROUP';

INSERT INTO core.establishment(urn, uid, name, establishment_type_id, establishment_status_id)
SELECT
    'POC100001',
    'POC-UID-001',
    'PoC Riverside Primary School',
    t.establishment_type_id,
    s.establishment_status_id
FROM ref.establishment_type t
CROSS JOIN ref.establishment_status s
WHERE t.code = 'POC_TYPE' AND s.code = 'POC_OPEN';

INSERT INTO core.establishment_provision(establishment_id, education_phase_id)
SELECT e.establishment_id, p.education_phase_id
FROM core.establishment e
CROSS JOIN ref.education_phase p
WHERE e.urn = 'POC100001' AND p.code = 'POC_PRIMARY';

INSERT INTO core.site(establishment_id, name, address_line_1, town, county, postcode)
SELECT
    establishment_id,
    'Main Site',
    '1 Example Road',
    'Cardiff',
    'South Glamorgan',
    'CF10 1AA'
FROM core.establishment
WHERE urn = 'POC100001';

INSERT INTO core.establishment_authority(establishment_id, authority_code, authority_name)
SELECT establishment_id, 'POC-LA', 'PoC Local Authority'
FROM core.establishment
WHERE urn = 'POC100001';

COMMIT;
