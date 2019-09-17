#!/bin/bash

while true
do
  echo "[`date`] Running RabbitMQ to Greenplum ..."
  psql -h localhost -d maxwell -U gpadmin -f ./greenplum-cdc/cdc_periodic_load.sql
  echo
  sleep 5
done

