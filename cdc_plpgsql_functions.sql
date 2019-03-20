/*
 * PL/PgSQL Functions for the CDC project
 *
 * $Id: cdc_plpgsql_functions.sql,v 1.19 2018/03/17 20:58:10 mgoddard Exp mgoddard $
 *
 */

CREATE OR REPLACE FUNCTION add_schema_name(schema TEXT, sql TEXT)
RETURNS TEXT
AS $$
global schema
global sql
if None == sql or None == schema:
  return None
sql = sql.upper()
import re
return re.sub(r'((?:CREATE|DROP|ALTER)\s+TABLE(?:\s+IF EXISTS)?)\s+(\w+)', r'\1 ' + schema + r'.\2', sql, re.IGNORECASE)
$$ LANGUAGE plpythonu;

-- Translate the MySQL dialect into a Greenplum/PostgreSQL flavor
CREATE OR REPLACE FUNCTION translate_sql (sql TEXT)
RETURNS TEXT
AS $$
global sql
if None == sql:
  return None

sql = sql.upper()

type_map = {
  'DOUBLE': 'FLOAT8',
  'DATETIME': 'TIMESTAMP',
  'LONGBLOB': 'BYTEA',
  'LONGTEXT': 'TEXT'
}

import re

# Remove any MySQL storage engine specs
sql = re.sub(r'\bENGINE\s*=\s*\S+', "", sql, flags=re.IGNORECASE)

# Remove any backticks around table names (may be too loose)
sql = re.sub(r'`', "", sql)

regex = re.compile(r'(TINYINT\(1\)|' + '|'.join(type_map.keys()) + ')')
# Function for use only within translate_sql()
def repl (m):
  m1 = m.group(1)
  rv = m1
  if m1 and m1 in type_map:
    rv = type_map[m1]
  elif 'TINYINT(1)' == m1:
    rv = 'SMALLINT'
  return rv

return regex.sub(repl, sql)
$$ LANGUAGE plpythonu;
-- GRANT EXECUTE ON FUNCTION translate_sql (FLOAT8, FLOAT8) TO maxwell;

-- Get the data type for the given column
-- DROP FUNCTION get_type (TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION get_type (s TEXT, t TEXT, c TEXT)
  RETURNS TEXT AS
$$
DECLARE
  rv TEXT;
BEGIN
  SELECT UPPER(data_type) INTO rv
  FROM information_schema.columns
  WHERE
    table_schema = s
    AND table_name = t
    AND column_name = c;
  RETURN rv;
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE;

-- Get the columns in the primary key for the given table
CREATE OR REPLACE FUNCTION get_pk_cols (s TEXT, t TEXT)
  RETURNS SETOF TEXT AS
$$
DECLARE
  rv TEXT;
BEGIN
  FOR rv IN SELECT a.attname
  FROM pg_index i
  JOIN pg_attribute a
    ON a.attrelid = i.indrelid
      AND a.attnum = ANY(i.indkey)
  WHERE
    i.indrelid = (s || '.' || t)::regclass
    AND i.indisprimary
  LOOP
    RETURN NEXT rv;
  END LOOP;
END;
$$
LANGUAGE 'plpgsql';

-- Scan and process the events (INSERT, UPDATE, DELETE) newer than last_ts
-- CREATE OR REPLACE FUNCTION process_events (last_ts TIMESTAMP)
CREATE OR REPLACE FUNCTION process_events ()
  RETURNS VOID AS
$$
DECLARE
  r maxwell_event%ROWTYPE;
  prev_ts TIMESTAMP;
  cur_ts TIMESTAMP;
  sql TEXT;
  op TEXT;
  key TEXT;
  val TEXT;
  to_set TEXT;
  pk_clause TEXT;
  ins_cols TEXT;
  ins_vals TEXT;
BEGIN
  SELECT ts from maxwell_ts INTO prev_ts;
  FOR r IN SELECT * FROM maxwell_event WHERE ts > prev_ts ORDER BY ts ASC
  LOOP
    op := UPPER(r.type); -- Can be INSERT, UPDATE, DELETE, or a DDL operation ('TABLE-CREATE', ...)
    cur_ts := r.ts;
    -- RAISE INFO 'DB: %, table: %, ts: %, op: %', r.database_name, r.table_name, r.ts, op;
    IF op = 'UPDATE' THEN
      RAISE INFO 'Got: %', op;
      to_set := '';
      sql := 'UPDATE ' || r.database_name || '.' || r.table_name || ' SET ';
      FOR key IN SELECT JSON_OBJECT_KEYS(r.event_json->'old')
      LOOP
        IF LENGTH(to_set) > 0 THEN
          to_set := to_set || ', '; -- Comma separate the list of "key = value"
        END IF;
        to_set := to_set || key || ' = ';
        val := quote_literal(r.event_json->'data'->>key);
        IF val IS NULL THEN
          to_set := to_set || 'NULL';
        ELSE
          to_set := to_set || val || '::' || get_type(r.database_name, r.table_name, key);
        END IF;
      END LOOP;
      sql := sql || to_set;
      pk_clause := '';
      sql := sql || ' WHERE ';
      FOR key IN SELECT get_pk_cols (r.database_name, r.table_name)
      LOOP
        IF LENGTH(pk_clause) > 0 THEN
          pk_clause := pk_clause || ' AND ';
        END IF;
        pk_clause := key || ' = ' || quote_literal(r.event_json->'data'->>key);
        pk_clause := pk_clause || '::' || get_type(r.database_name, r.table_name, key);
      END LOOP;
      IF LENGTH(pk_clause) > 0 THEN -- Require a primary key
        sql := sql || pk_clause || ';';
      ELSE
        RAISE INFO 'No primary key on table % -- aborting the UPDATE', r.database_name || '.' || r.table_name;
        sql := NULL;
      END IF;
    ELSIF op = 'INSERT' THEN
      RAISE INFO 'Got: %', op;
      sql := 'INSERT INTO ' || r.database_name || '.' || r.table_name;
      ins_cols = '';
      ins_vals = '';
      FOR key IN SELECT JSON_OBJECT_KEYS(r.event_json->'data')
      LOOP
        IF LENGTH(ins_cols) > 0 THEN
          ins_cols := ins_cols || ', ';
          ins_vals := ins_vals || ', ';
        END IF;
        ins_cols := ins_cols || key;
        val := quote_literal(r.event_json->'data'->>key);
        IF val IS NULL THEN
          ins_vals := ins_vals || 'NULL';
        ELSE
          ins_vals := ins_vals || val || '::' || get_type(r.database_name, r.table_name, key);
        END IF;
      END LOOP;
      sql := sql || '(' || ins_cols || ') VALUES (' || ins_vals || ');';
    ELSIF op = 'DELETE' THEN
      RAISE INFO 'Got: %', op;
      -- Handle DELETE
      sql := 'DELETE FROM ' || r.database_name || '.' || r.table_name || ' WHERE ';
      pk_clause := '';
      FOR key IN SELECT get_pk_cols (r.database_name, r.table_name)
      LOOP
        IF LENGTH(pk_clause) > 0 THEN
          pk_clause := pk_clause || ' AND ';
        END IF;
        pk_clause := key || ' = ' || quote_literal(r.event_json->'data'->>key);
        pk_clause := pk_clause || '::' || get_type(r.database_name, r.table_name, key);
      END LOOP;
      sql := sql || pk_clause || ';';
    ELSIF op = 'DATABASE-CREATE' THEN
      RAISE INFO 'Got: %', op;
      -- Create a schema
      sql := 'CREATE SCHEMA ' || r.database_name || ';';
    ELSIF op = 'DATABASE-DROP' THEN
      RAISE INFO 'Got: %', op;
      -- Drop the schema with CASCADE
      sql := 'DROP SCHEMA ' || r.database_name || ' CASCADE;';
    ELSIF op = 'TABLE-CREATE' THEN
      RAISE INFO 'Got: %', op;
      -- Create a table within an existing schema
      sql := add_schema_name(r.database_name, translate_sql(r.event_json->>'sql')) || ';';
    ELSIF op = 'TABLE-ALTER' THEN
      RAISE INFO 'Got: %', op;
      -- Alter table (include schema)
      sql := add_schema_name(r.database_name, translate_sql(r.event_json->>'sql')) || ';';
    ELSIF op = 'TABLE-DROP' THEN
      RAISE INFO 'Got: %', op;
      -- Drop table (include schema)
      sql := add_schema_name(r.database_name, translate_sql(r.event_json->>'sql')) || ';';
    ELSE
      RAISE INFO 'op: % is not one I care about', op;
    END IF;
    IF sql IS NOT NULL THEN
      RAISE INFO 'SQL: %', sql;
      EXECUTE sql;
    ELSE
      RAISE INFO 'Nothing to do';
    END IF;
  END LOOP;
  IF cur_ts > prev_ts THEN
    RAISE INFO 'Updating tracking table';
    EXECUTE 'UPDATE maxwell_ts SET ts = ' || quote_literal(cur_ts) || '::TIMESTAMP;';
  ELSE
    RAISE INFO 'No update to tracking table';
  END IF;
END;
$$
LANGUAGE 'plpgsql';
