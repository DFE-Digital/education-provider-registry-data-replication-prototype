CREATE OR REPLACE FUNCTION read_model.refresh_establishment_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM read_model.refresh_establishment(OLD.establishment_id);

        RETURN OLD;

    END IF;

    IF TG_OP = 'UPDATE'
    AND OLD.establishment_id IS DISTINCT
    FROM NEW.establishment_id THEN
        PERFORM read_model.refresh_establishment(OLD.establishment_id);

    END IF;

    PERFORM read_model.refresh_establishment(NEW.establishment_id);

    RETURN NEW;

    END;

$$;

CREATE TRIGGER refresh_establishment
AFTER INSERT OR UPDATE OR DELETE ON core.establishment
FOR EACH ROW
EXECUTE FUNCTION read_model.refresh_establishment_trigger();

ALTER TABLE core.establishment
ENABLE REPLICA TRIGGER refresh_establishment;

CREATE TRIGGER refresh_establishment_from_site
AFTER INSERT OR UPDATE OR DELETE ON core.site
FOR EACH ROW
EXECUTE FUNCTION read_model.refresh_establishment_trigger();

ALTER TABLE core.site
ENABLE REPLICA TRIGGER refresh_establishment_from_site;

CREATE TRIGGER refresh_establishment_from_authority
AFTER INSERT OR UPDATE OR DELETE ON core.establishment_authority
FOR EACH ROW
EXECUTE FUNCTION read_model.refresh_establishment_trigger();

ALTER TABLE core.establishment_authority
ENABLE REPLICA TRIGGER refresh_establishment_from_authority;

CREATE OR REPLACE FUNCTION read_model.refresh_establishments_for_type()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM read_model.refresh_establishment(e.establishment_id)
    FROM core.establishment AS e
    WHERE e.establishment_type_id = NEW.establishment_type_id;

    RETURN NEW;

    END;

$$;

CREATE TRIGGER refresh_establishments_from_type
AFTER UPDATE ON ref.establishment_type
FOR EACH ROW
EXECUTE FUNCTION read_model.refresh_establishments_for_type();

ALTER TABLE ref.establishment_type
ENABLE REPLICA TRIGGER refresh_establishments_from_type;
