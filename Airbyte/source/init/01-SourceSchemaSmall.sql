CREATE SCHEMA core;

CREATE TABLE core.local_authority
(
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL
);

CREATE TABLE core.establishment
(
    urn INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    local_authority_id INTEGER NOT NULL
        REFERENCES core.local_authority(id)
);

CREATE TABLE core.site
(
    id INTEGER PRIMARY KEY,
    establishment_urn INTEGER NOT NULL
        REFERENCES core.establishment(urn),
    address_line_1 TEXT,
    town TEXT,
    postcode TEXT
);

INSERT INTO core.local_authority (id, name)
VALUES
    (1, 'Test Local Authority');

INSERT INTO core.establishment
(
    urn,
    name,
    local_authority_id
)
VALUES
    (1000001, 'Alpha Academy', 1),
    (1000002, 'Beta School', 1);

INSERT INTO core.site
(
    id,
    establishment_urn,
    address_line_1,
    town,
    postcode
)
VALUES
    (1, 1000001, '1 Test Street', 'Testville', 'TE1 1ST'),
    (2, 1000002, '2 Example Road', 'Testville', 'TE1 2ST');