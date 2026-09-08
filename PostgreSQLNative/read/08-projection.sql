CREATE SCHEMA IF NOT EXISTS read_model;

CREATE TABLE read_model.establishment (
    establishment_id BIGINT PRIMARY KEY, urn TEXT, uid TEXT, name TEXT NOT NULL, establishment_number TEXT, establishment_type_id BIGINT, establishment_type_name TEXT, establishment_status_id BIGINT, establishment_status_name TEXT, education_phase_id BIGINT, education_phase_name TEXT, sites JSONB NOT NULL DEFAULT '[]'::jsonb, authorities JSONB NOT NULL DEFAULT '[]'::jsonb
);

CREATE OR REPLACE FUNCTION read_model.refresh_establishment(
    p_establishment_id BIGINT
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM core.establishment AS e
        WHERE e.establishment_id = p_establishment_id
    ) THEN
        DELETE
        FROM read_model.establishment
        WHERE establishment_id = p_establishment_id;

        RETURN;

    END IF;

    INSERT INTO read_model.establishment (
        establishment_id, urn, uid, name, establishment_number, establishment_type_id, establishment_type_name, establishment_status_id, establishment_status_name, education_phase_id, education_phase_name, sites, authorities
    )
    SELECT
    e.establishment_id, e.urn, e.uid, e.name, e.establishment_number, e.establishment_type_id, et.name, e.establishment_status_id, es.name, p.education_phase_id, ep.name, COALESCE(
        (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'site_id', s.site_id, 'name', s.name, 'address_line_1', s.address_line_1, 'address_line_2', s.address_line_2, 'town', s.town, 'county', s.county, 'postcode', s.postcode
                )
                ORDER BY s.site_id
            )
            FROM core.site AS s
            WHERE s.establishment_id = e.establishment_id
        ), '[]'::jsonb
    ), COALESCE(
        (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'establishment_authority_id', ea.establishment_authority_id, 'authority_code', ea.authority_code, 'authority_name', ea.authority_name
                )
                ORDER BY ea.establishment_authority_id
            )
            FROM core.establishment_authority AS ea
            WHERE ea.establishment_id = e.establishment_id
        ), '[]'::jsonb
    )
    FROM core.establishment AS e
    JOIN ref.establishment_type AS et
        ON et.establishment_type_id = e.establishment_type_id
    JOIN ref.establishment_status AS es
        ON es.establishment_status_id = e.establishment_status_id
    LEFT JOIN core.establishment_provision AS p
        ON p.establishment_id = e.establishment_id
    LEFT JOIN ref.education_phase AS ep
        ON ep.education_phase_id = p.education_phase_id
    WHERE e.establishment_id = p_establishment_id
    ON CONFLICT (establishment_id)
    DO UPDATE SET
    urn = EXCLUDED.urn, uid = EXCLUDED.uid, name = EXCLUDED.name, establishment_number = EXCLUDED.establishment_number, establishment_type_id = EXCLUDED.establishment_type_id, establishment_type_name = EXCLUDED.establishment_type_name, establishment_status_id = EXCLUDED.establishment_status_id, establishment_status_name = EXCLUDED.establishment_status_name, education_phase_id = EXCLUDED.education_phase_id, education_phase_name = EXCLUDED.education_phase_name, sites = EXCLUDED.sites, authorities = EXCLUDED.authorities;

    END;

$$;
