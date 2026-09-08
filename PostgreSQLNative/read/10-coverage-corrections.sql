CREATE TRIGGER refresh_establishment_from_provision
AFTER INSERT OR UPDATE OR DELETE ON core.establishment_provision
FOR EACH ROW
EXECUTE FUNCTION read_model.refresh_establishment_trigger();

ALTER TABLE core.establishment_provision
ENABLE REPLICA TRIGGER refresh_establishment_from_provision;

CREATE FUNCTION read_model.refresh_for_status()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM read_model.refresh_establishment(e.establishment_id)
    FROM core.establishment e
    WHERE e.establishment_status_id = NEW.establishment_status_id;

    RETURN NEW;

END
$$;

CREATE TRIGGER refresh_from_status AFTER INSERT OR UPDATE ON ref.establishment_status
FOR EACH ROW
EXECUTE FUNCTION read_model.refresh_for_status();

ALTER TABLE ref.establishment_status
ENABLE REPLICA TRIGGER refresh_from_status;

CREATE FUNCTION read_model.refresh_for_phase()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM read_model.refresh_establishment(e.establishment_id)
    FROM core.establishment e
    JOIN core.establishment_provision p ON p.establishment_id = e.establishment_id
    WHERE p.education_phase_id = NEW.education_phase_id;

    RETURN NEW;

END
$$;

CREATE TRIGGER refresh_from_phase AFTER INSERT OR UPDATE ON ref.education_phase
FOR EACH ROW
EXECUTE FUNCTION read_model.refresh_for_phase();

ALTER TABLE ref.education_phase
ENABLE REPLICA TRIGGER refresh_from_phase;

CREATE TRIGGER refresh_establishments_from_type_insert AFTER INSERT ON ref.establishment_type
FOR EACH ROW
EXECUTE FUNCTION read_model.refresh_establishments_for_type();

ALTER TABLE ref.establishment_type
ENABLE REPLICA TRIGGER refresh_establishments_from_type_insert;
