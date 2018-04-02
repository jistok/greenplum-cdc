# Change Data Capture (CDC) from MySQL to Greenplum Database

## TODO
1. Add some scripts to handle periodic Greenplum maintenance
   * [Vacuum tables and catalog](https://gpdb.docs.pivotal.io/43170/admin_guide/managing/maintain.html)
2. Add another consumer group to "fan out" fan out to Elastic Search
   * Try just using a single index for all tables
   * Form the `doc_id` using the primary key values from the table?
   * Also index/store the DB name and the table name

## See Also
* [Canal](https://github.com/siddontang/go-mysql#canal), a Go lang binlog replicator

