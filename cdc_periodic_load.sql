-- Kafka to event table
INSERT INTO maxwell_event
SELECT
  -- The precision of 'ts' varies by context; it's greater for the DDL events, for some reason.
  to_timestamp(case when length(events->>'ts') = 13 then ((events->>'ts')::bigint/1000)::int else (events->>'ts')::int end)
  , events->>'database'
  , events->>'table'
  , events->>'type'
  , events
FROM maxwell_rabbitmq;

-- Event table to replica of the MySQL table
SELECT process_events();
