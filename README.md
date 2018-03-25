# Change Data Capture (CDC) from MySQL to Greenplum Database

## TODO
1. What happens when there are DDL statements (new table, change to table, etc.)?
   * Possible to capture these via Maxwell's Daemon?
   * Or, can we create triggers?
   * Put the DDL statements into a different Kafka topic?
   * Periodically, poll the DB and diff the DDL coming out?
   * If DML statements in the Kafka topic involve tables we don't know about, this'll break.
   * [This article](http://debezium.io/blog/2016/08/02/capturing-changes-from-mysql/) may have ideas on DDL capture.
1. Add another consumer group to "fan out" fan out to Elastic Search
   * Try just using a single index for all tables
   * Form the `doc_id` using the primary key values from the table?
   * Also index/store the DB name and the table name

