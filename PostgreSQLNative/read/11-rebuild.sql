BEGIN;

LOCK TABLE core.establishment, core.establishment_provision, core.site, core.establishment_authority, ref.establishment_type, ref.establishment_status, ref.education_phase IN SHARE MODE;

LOCK TABLE read_model.establishment IN SHARE ROW EXCLUSIVE MODE;

DELETE
FROM read_model.establishment;

SELECT read_model.refresh_establishment(establishment_id)
FROM core.establishment
ORDER BY establishment_id;

COMMIT;
