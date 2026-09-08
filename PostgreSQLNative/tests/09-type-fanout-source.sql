UPDATE ref.establishment_type
SET name = 'PoC Community Primary School - Updated'
WHERE code = 'POC_TYPE'
RETURNING establishment_type_id, code, name;
