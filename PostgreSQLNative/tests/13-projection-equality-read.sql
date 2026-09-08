DO $$
BEGIN
    IF EXISTS (WITH expected AS (    SELECT
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
        )
        (SELECT *
            FROM expected EXCEPT SELECT *
            FROM read_model.establishment)
        UNION ALL
        (SELECT *
            FROM read_model.establishment EXCEPT SELECT *
            FROM expected))
    THEN
        RAISE EXCEPTION 'Physical projection differs from current raw-table projection';

    END IF;

END
$$;
