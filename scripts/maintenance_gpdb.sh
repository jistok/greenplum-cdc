#!/bin/bash

DBNAME="maxwell"
SYSTABLES="' pg_catalog.' || relname || ';' from pg_class a, pg_namespace b 
where a.relnamespace=b.oid and b.nspname='pg_catalog' and a.relkind='r'"
psql -tc "SELECT 'VACUUM' || $SYSTABLES" $DBNAME | psql -a $DBNAME
reindexdb --system -d $DBNAME
analyzedb -a -s pg_catalog -d $DBNAME

