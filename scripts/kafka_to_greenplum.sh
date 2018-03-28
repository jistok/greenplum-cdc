#!/bin/bash

while `true`
do
  echo "[`date`] Running Kafka to Greenplum ..."
  psql -f cdc_periodic_load.sql maxwell
  echo
  sleep 5
done

