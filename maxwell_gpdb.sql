/*
 * MySQL Change Data Capture (CDC) into Greenplum Database
 * Ref.
 *  http://maxwells-daemon.io/
 *  https://github.com/mgoddard-pivotal/gpdb-kafka-round-trip
 *  https://gpdb.docs.pivotal.io/500/admin_guide/query/topics/json-data.html
 *  https://gpdb.docs.pivotal.io/43180/admin_guide/ddl/ddl-partition.html#topic67
 *
 * $Id: maxwell_gpdb.sql,v 1.11 2018/03/17 20:46:36 mgoddard Exp mgoddard $
 *
 */

-- 1. This is the external table to use for accessing all the Maxwell's Daemon
-- MySQL CDC data, via Kafka
DROP EXTERNAL TABLE IF EXISTS maxwell_kafka;
CREATE EXTERNAL WEB TABLE maxwell_kafka
(events JSON)
EXECUTE '$HOME/go-kafkacat --broker=localhost:9092 consume --group=GPDB_Consumer_Group maxwell --eof 2>>$HOME/`printf "kafka_consumer_%02d.log" $GP_SEGMENT_ID`'
ON ALL FORMAT 'TEXT' (DELIMITER 'OFF' NULL '')
LOG ERRORS SEGMENT REJECT LIMIT 1 PERCENT;

-- 2. This table archives the entire event stream, as JSON, but with certain fields
-- pulled out into their own columns
DROP TABLE IF EXISTS maxwell_event;
CREATE TABLE maxwell_event
(
  ts TIMESTAMP -- TODO verify the time zone (is this UTC?)
  , database_name TEXT
  , table_name TEXT
  , type TEXT
  , event_json JSON
)
WITH (APPENDONLY=true, COMPRESSTYPE=zlib, COMPRESSLEVEL=5)
DISTRIBUTED RANDOMLY
PARTITION BY RANGE (ts)
(
  START ('2018-03-01'::TIMESTAMP) -- FIXME: these start and end dates may vary
  END ('2019-01-01'::TIMESTAMP)
  EVERY (INTERVAL '1 MONTH')
  , DEFAULT PARTITION outliers
);

-- 3. Store some metadata about loading and seed it with an "old" date.
CREATE TABLE maxwell_ts (ts TIMESTAMP);
INSERT INTO maxwell_ts (ts) VALUES ('2010-01-01'::TIMESTAMP);

-- 4. Periodically, load the AO table from the Kafka external table
INSERT INTO maxwell_event
SELECT
  to_timestamp((events->>'ts')::int)
  , events->>'database'
  , events->>'table'
  , events->>'type'
  , events
FROM maxwell_kafka;

-- 5. Follow up item 4 with this, to load the Greenplum replica of the MySQL table
-- (this requires the PL/PGSQL functions to be loaded; see cdc_plpgsql_functions.sql)
SELECT process_events();

-- NOTE: the items below are for documentation and idea purposes; they aren't in the workflow.
SELECT *
FROM maxwell_event
WHERE ts > '2018-03-13 17:55:28'::timestamp
ORDER BY ts ASC;

/* From here, you could:
 * (a) Quit (maybe the event log is sufficient)
 * (b) Load a replica of the original table, with the same types, replaying the events on this table
 * (c) Use a PL/Python or other type of function to get at the various fields within the 'data' field
 */

/*
 * Build an example table for the following data:
 * {"database":"demo","table":"person","type":"insert","ts":1520932599,"xid":21460,"commit":true,"data":{"id":3,"first":"Erlich","last":"Bachman","active_yn":0}}
 * 
 * Map the "database" field to a schema
 * Check for existence of schema 'demo':  SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'demo';
 */

/*
Let's try starting with this Spring Music table, manually:

gpadmin=# \d music.album
                           Table "music.album"
    Column    |          Type          |            Modifiers            
--------------+------------------------+---------------------------------
 id           | character varying(40)  | not null
 album_id     | character varying(255) | default NULL::character varying
 artist       | character varying(255) | default NULL::character varying
 genre        | character varying(255) | default NULL::character varying
 release_year | character varying(255) | default NULL::character varying
 title        | character varying(255) | default NULL::character varying
 track_count  | integer                | not null
Indexes:
    "album_pkey" PRIMARY KEY, btree (id)
Distributed by: (id)

*/

-- Example of pulling column values from the events table (Spring Music app)
INSERT INTO music.album
WITH events AS (
  SELECT event_json->'data' evt
  FROM maxwell_event
  WHERE
    database_name = 'music'
    AND table_name = 'album'
    AND type = 'insert'
    -- AND ts >= '2018-03-14 18:05:07'::TIMESTAMP
)
SELECT
  evt->>'id' id -- FIXME: Just case *all* of the values
  , evt->>'album_id'
  , evt->>'artist'
  , evt->>'genre'
  , evt->>'release_year'
  , evt->>'title'
  , (evt->>'track_count')::int -- NOTE: for non-TEXT types, a cast must be used
FROM events;

-- Fetch the primary key(s) for a table
-- Ref. https://wiki.postgresql.org/wiki/Retrieve_primary_key_columns
SELECT a.attname, format_type(a.atttypid, a.atttypmod) AS data_type
FROM   pg_index i
JOIN   pg_attribute a ON a.attrelid = i.indrelid
                     AND a.attnum = ANY(i.indkey)
WHERE  i.indrelid = 'music.album'::regclass
AND    i.indisprimary;

-- Fetch data types for columns in a table
SELECT attname, format_type(atttypid, atttypmod) AS type
FROM pg_attribute
WHERE
  attrelid = 'music.album'::regclass
  AND attnum > 0
  AND NOT attisdropped
ORDER BY attnum;

-- Dedup using window function
INSERT INTO dest (a,b,c,d)
SELECT a,b,c,d
FROM (
  SELECT a,b,c,d,
  ROW_NUMBER() OVER (PARTITION BY a,b,c,d) AS rnum
  FROM source_xt
) AS src
WHERE rnum = 1;

-- ** MySQL ** Show all (schema/db, table) names
SELECT table_schema, table_name
FROM INFORMATION_SCHEMA.tables
ORDER BY table_schema, table_name;

/* MySQL: dump DDL for one, or all, databases
[gpadmin@gpdb ~]$ cat mysql_dump_ddl.sh 
#!/bin/bash

user="root"
pass="music"
#user="music"
#pass="music"
db="music"
host="localhost"

# NOTES:
# - Column names will be double quoted
# - Some types might not match; e.g. "INT(11)" will have to become "INT"

# SINGLE DB
#mysqldump --compatible=postgresql --default-character-set=utf8 -d -u $user -p$pass -h $host $db

# ALL DBs
mysqldump --compatible=postgresql --default-character-set=utf8 -d -u $user -p -h $host --all-databases
*/

-- We want streaming read -- make a single pass over all this input data
select database_name, table_name, type, ts, event_json
from maxwell_event
where ts > last_ts
order by 1, 2, 3, 4;


