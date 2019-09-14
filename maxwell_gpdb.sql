-- MySQL Change Data Capture (CDC) into Greenplum Database

-- 1. This is the external table to use for accessing all the Maxwell's Daemon MySQL CDC data, via RabbitMQ
-- FIXME: the value passwd to -uri must be set up per install
DROP EXTERNAL TABLE IF EXISTS maxwell_rabbitmq;
CREATE EXTERNAL WEB TABLE maxwell_rabbitmq
(events JSON)
EXECUTE '$HOME/rabbitmq -exchange maxwell -exchange-type fanout -key mysql-cdc -uri "amqp://guest:guest@192.168.1.7:5672/" 2>>$HOME/rabbitmq.log'
ON MASTER FORMAT 'TEXT' (DELIMITER 'OFF' NULL '')
SEGMENT REJECT LIMIT 1 PERCENT;

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
  START ('2019-03-01'::TIMESTAMP) -- FIXME: these start and end dates may vary
  END ('2019-12-01'::TIMESTAMP)
  EVERY (INTERVAL '1 MONTH')
  , DEFAULT PARTITION outliers
);

-- 3. Store some metadata about loading and seed it with an "old" date
DROP TABLE IF EXISTS maxwell_ts;
CREATE TABLE maxwell_ts (ts TIMESTAMP) DISTRIBUTED RANDOMLY;
INSERT INTO maxwell_ts (ts) VALUES ('2010-01-01'::TIMESTAMP);
