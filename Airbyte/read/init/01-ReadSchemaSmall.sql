CREATE USER airbyte_writer
WITH PASSWORD 'airbyte';

GRANT CONNECT
ON DATABASE airbyte_read
TO airbyte_writer;

GRANT CREATE, TEMPORARY
ON DATABASE airbyte_read
TO airbyte_writer;

CREATE SCHEMA airbyte
AUTHORIZATION airbyte_writer;

CREATE SCHEMA read_model;