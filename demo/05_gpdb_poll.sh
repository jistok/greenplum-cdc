#!/bin/bash

while true
do
  echo "[`date`] Polling the music.album table in Greenplum ..."
  echo "SELECT * FROM music.album ORDER BY artist, title;" | psql -h localhost -d maxwell -U gpadmin
  echo
  sleep 5
done

