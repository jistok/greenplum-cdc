#!/bin/bash

while true
do
  echo "[`date`] Polling the music.album table in MySQL ..."
  echo "SELECT * FROM music.album ORDER BY artist, title;" | mysql --table -u music music
  echo
  sleep 5
done

