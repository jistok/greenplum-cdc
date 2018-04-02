-- MySQL Change Data Capture (CDC) into Greenplum Database

-- 1. This is the external table to use for accessing all the Maxwell's Daemon MySQL CDC data, via Kafka
DROP EXTERNAL TABLE IF EXISTS maxwell_kafka;
CREATE EXTERNAL WEB TABLE maxwell_kafka
(events JSON)
EXECUTE '$HOME/go-kafkacat --broker=localhost:9092 consume --group=GPDB_Consumer_Group maxwell --eof 2>>$HOME/`printf "kafka_consumer_%02d.log" $GP_SEGMENT_ID`'
ON ALL FORMAT 'TEXT' (DELIMITER 'OFF' NULL '')
LOG ERRORS SEGMENT REJECT LIMIT 1 PERCENT;

-- 2. This table archives the entire event stream, as JSON, but with certain fields pulled out into their own columns
DROP TABLE IF EXISTS maxwell_event;
CREATE TABLE maxwell_event
(
  ts TIMESTAMP
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

-- 3. Store some metadata about loading and seed it with an "old" date
CREATE TABLE maxwell_ts (ts TIMESTAMP);
INSERT INTO maxwell_ts (ts) VALUES ('2010-01-01'::TIMESTAMP);

