# Change Data Capture (CDC) from MySQL to Greenplum Database

## Abstract
When a Pivotal Cloud Foundry operator installs PCF, it’s very likely they will
choose to deploy the MySQL database tile (this is my personal observation).
With this in place, developers can easily self-provision a persistence layer
for their applications.  These are optimized for transactional workloads, but
not large data sets and analytical queries.  This is where Pivotal Greenplum
Database can be brought in, to provide that long-term, deep analytical query
back end.  This document introduces an approach to linking these two data
backends.

## Approach
* [Maxwell's Daemon](http://maxwells-daemon.io/) captures any DDL or DML operations in MySQL and publishes them to a Kafka topic, in a JSON format.
* Apache Kafka provides the messaging layer.
* Greenplum Database external tables, combined with [this Kafka integration approach](https://github.com/mgoddard-pivotal/gpdb-kafka-round-trip) enables Greenplum to ingest these MySQL events.
* Periodically (see `./cdc_periodic_load.sql`):
  - A Greenplum query polls the Kafka topic, inserting new events into the `maxwell_event` table
  - Another Greenplum query runs the `process_events` PL/PGSQL function, which maintains the replicas of the MySQL objects

## Running the demo (single VM with Greenplum 5.x installed and running)
![View of tabbed terminal running the demo](./images/demo_vm_shell_view.png)
* Grab a copy of the Kafka demo referenced above:
  ```
  $ git clone https://github.com/mgoddard-pivotal/gpdb-kafka-round-trip.git
  ```
* Follow the procedure [detailed here](https://github.com/mgoddard-pivotal/gpdb-kafka-round-trip) to get the `go-kafkacat` binary built.  Note that there some precompiled binaries in the `./bin` directory, which would make this simpler if there is one for your OS, though you will have to install librdkafka in any case.
* Start up Kafka:
  - Edit the `kafka_env.sh` as required for your setup
  - Start Zookeeper: `$ ./zk_start.sh`
  - Start Kafka: `$ ./kafka_start.sh` (See "Kafka log" tab in the picture)
* Install MySQL server, configure it per the "Row based replication" section in the [Maxwell's Daemon quick start](http://maxwells-daemon.io/quickstart/), and start it up.
* Run the `GRANT` commands shown in the "Mysql permissions" section of that Maxwell's Daemon quick start.
* Download and extract the Maxwell's Daemon:
  ```
  $ curl -sLo - https://github.com/zendesk/maxwell/releases/download/v1.13.2/maxwell-1.13.2.tar.gz | tar zxvf -
  ```
* Start Maxwell's Daemon (See "Maxwell's Daemon" tab in the picture):
  ```
  $ ./maxwell-1.13.2/bin/maxwell --output_ddl=true --user='maxwell' --password='maxwell' --host='127.0.0.1' --producer=kafka --kafka.bootstrap.servers=localhost:9092
  ```
* Create the MySQL database "music", along with a user, for the [Spring Music app](https://github.com/cloudfoundry-samples/spring-music):
  ```
  mysql> CREATE DATABASE MUSIC;
  mysql> GRANT ALL ON music.* TO 'music'@'localhost' IDENTIFIED BY 'music';
  ```
* Simulate a Cloud Foundry app's environment, with a binding to a MySQL instance:
  ```
  $ export VCAP_APPLICATION=$( cat ./VCAP_APPLICATION.json )
  $ export VCAP_SERVICES=$( cat ./VCAP_SERVICES_MYSQL.json )
  ```
* Get a local copy of the Spring music app:
  ```
  $ git clone https://github.com/cloudfoundry-samples/spring-music.git
  ```
* Build the app per its instructions
* Start the Spring Music app (from within the `spring-music` directory -- see "Spring Music" tab in the picture):
  ```
  $ java -jar ./build/libs/spring-music.jar
  ```
* While logged in as `gpadmin`, run the following to set up the tables and functions to handle CDC:
  ```
  $ createdb maxwell
  $ psql maxwell -f ./maxwell_gpdb.sql # Alter the 'PARTITION BY RANGE' endpoints as necessary
  $ createlang plpythonu maxwell
  $ psql maxwell -f ./cdc_plpgsql_functions.sql
  ```
* Start the periodic load into Greenplum (See "Kafka => Greenplum" tab in the picture):
  ```
  while true
  do
    echo "[`date`] Running Kafka to Greenplum ..."
    psql maxwell -f ./cdc_periodic_load.sql
    echo
    sleep 5
  done
  ```
* Poll the MySQL DB (See "MySQL poll" tab in the picture):
  ```
  while true
  do
    echo "[`date`] Polling the music.album table in MySQL ..."
    echo "SELECT * FROM music.album ORDER BY artist, title;" | mysql --table -u music music
    echo
    sleep 5
  done
  ```
* Poll Greenplum (See the "Greenplum poll" tab in the picture):
  ```
  while true
  do
    echo "[`date`] Polling the music.album table in Greenplum ..."
    echo "SELECT * FROM music.album ORDER BY artist, title;" | psql maxwell
    echo
    sleep 5
  done
  ```
* Access the [Spring Music UI](http://localhost:8080/) and make some changes to the data, then you should
be able to see those changes occur in the Greenplum table via the "Greenplum poll" tab.
* If you log into MySQL as "root", then run `CREATE DATABASE some_db_name`, you should be able to observe
this event in the "Kafka => Greenplum" tab.  Here are some other DDL operations to try:
  - `CREATE TABLE`
  - `ALTER TABLE`
  - `DROP TABLE`
  - `DROP DATABASE`

## Demo environment
Note: the library which must be installed is highlighted in **bold**; this is mentioned in the above GitHub repo.
<pre>
[root@gpdb ~]# cat /etc/redhat-release 
CentOS release 6.9 (Final)
[root@gpdb ~]# uname -a
Linux gpdb 2.6.32-696.el6.x86_64 #1 SMP Tue Mar 21 19:29:05 UTC 2017 x86_64 x86_64 x86_64 GNU/Linux
[root@gpdb ~]# ldd ~gpadmin/go-kafkacat 
	linux-vdso.so.1 =>  (0x00007ffc7cb2d000)
	<b>librdkafka.so.1 => /usr/local/lib/librdkafka.so.1 (0x00007fd06b1bf000)</b>
	libpthread.so.0 => /lib64/libpthread.so.0 (0x0000003b0d400000)
	libc.so.6 => /lib64/libc.so.6 (0x0000003b0cc00000)
	libsasl2.so.2 => /usr/lib64/libsasl2.so.2 (0x0000003b1e000000)
	libssl.so.10 => /usr/lib64/libssl.so.10 (0x0000003b1cc00000)
	libcrypto.so.10 => /usr/lib64/libcrypto.so.10 (0x0000003b19800000)
	libz.so.1 => /lib64/libz.so.1 (0x0000003b0dc00000)
	libdl.so.2 => /lib64/libdl.so.2 (0x0000003b0c800000)
	librt.so.1 => /lib64/librt.so.1 (0x0000003b0d800000)
	/lib64/ld-linux-x86-64.so.2 (0x0000003b0c400000)
	libresolv.so.2 => /lib64/libresolv.so.2 (0x0000003b0e800000)
	libcrypt.so.1 => /lib64/libcrypt.so.1 (0x0000003b18400000)
	libgssapi_krb5.so.2 => /lib64/libgssapi_krb5.so.2 (0x0000003b1c000000)
	libkrb5.so.3 => /lib64/libkrb5.so.3 (0x0000003b1a800000)
	libcom_err.so.2 => /lib64/libcom_err.so.2 (0x0000003b18c00000)
	libk5crypto.so.3 => /lib64/libk5crypto.so.3 (0x0000003b1b400000)
	libfreebl3.so => /lib64/libfreebl3.so (0x0000003b17000000)
	libkrb5support.so.0 => /lib64/libkrb5support.so.0 (0x0000003b1a400000)
	libkeyutils.so.1 => /lib64/libkeyutils.so.1 (0x0000003b19000000)
	libselinux.so.1 => /lib64/libselinux.so.1 (0x0000003b0e400000)
</pre>

## Deploying Maxwell's Daemon in Cloud Foundry
1. Create an instance of the MySQL service (NOTE: this won't work yet since it requires the escalated privileges to perform the required `GRANT` operations).
1. Create an instance of a Kafka service (TBD on which tile will provide this; Stark & Wayne's tile is outdated).
1. Copy `./manifest.yml` and `./run_maxwell.py` into the root of the Maxwell's Daemon project you downloaded.
1. From within that directory: `cf push --no-start`
1. Bind those two service intances to the app; e.g. `cf bs maxwell mysql && cf bs maxwell kafka`
1. Start Maxwell's Daemon: `cf start maxwell`

## TODO
0. Switch from Kafka to RabbitMQ
1. Add some scripts to handle periodic Greenplum maintenance
   * [Vacuum tables and catalog](https://gpdb.docs.pivotal.io/43170/admin_guide/managing/maintain.html)
2. Add another consumer group to "fan out" fan out to Elastic Search
   * Try just using a single index for all tables
   * Form the `doc_id` using the primary key values from the table?
   * Also index/store the DB name and the table name
3. Consider how an "undo" would work, since we can reverse any action.
4. Enhance demo to include data from a µ-services architecture, like [this one](https://spring.io/blog/2015/07/14/microservices-with-spring)

## See also
* [Canal](https://github.com/siddontang/go-mysql#canal), a Go lang binlog replicator

## Known issues
After the VM running the whole demo crashed, I encountered this state upon restarting Maxwell's Daemon:
```
10:30:07,078 INFO  BinlogConnectorLifecycleListener - Binlog connected.
10:30:07,129 WARN  BinlogConnectorLifecycleListener - Event deserialization failure.
com.github.shyiko.mysql.binlog.event.deserialization.EventDataDeserializationException: Failed to deserialize data of EventHeaderV4{timestamp=1522558072000, eventType=UPDATE_ROWS, serverId=1, headerLength=19, dataLength=89, nextPosition=48082965, flags=0}
	at com.github.shyiko.mysql.binlog.event.deserialization.EventDeserializer.deserializeEventData(EventDeserializer.java:216) ~[mysql-binlog-connector-java-0.13.0.jar:0.13.0]
	at com.github.shyiko.mysql.binlog.event.deserialization.EventDeserializer.nextEvent(EventDeserializer.java:184) ~[mysql-binlog-connector-java-0.13.0.jar:0.13.0]
	at com.github.shyiko.mysql.binlog.BinaryLogClient.listenForEventPackets(BinaryLogClient.java:890) [mysql-binlog-connector-java-0.13.0.jar:0.13.0]
	at com.github.shyiko.mysql.binlog.BinaryLogClient.connect(BinaryLogClient.java:559) [mysql-binlog-connector-java-0.13.0.jar:0.13.0]
	at com.github.shyiko.mysql.binlog.BinaryLogClient$7.run(BinaryLogClient.java:793) [mysql-binlog-connector-java-0.13.0.jar:0.13.0]
	at java.lang.Thread.run(Thread.java:748) [?:1.8.0_161]
Caused by: com.github.shyiko.mysql.binlog.event.deserialization.MissingTableMapEventException: No TableMapEventData has been found for table id:1116691496960. Usually that means that you have started reading binary log 'within the logical event group' (e.g. from WRITE_ROWS and not proceeding TABLE_MAP
	at com.github.shyiko.mysql.binlog.event.deserialization.AbstractRowsEventDataDeserializer.deserializeRow(AbstractRowsEventDataDeserializer.java:98) ~[mysql-binlog-connector-java-0.13.0.jar:0.13.0]
	at com.github.shyiko.mysql.binlog.event.deserialization.UpdateRowsEventDataDeserializer.deserializeRows(UpdateRowsEventDataDeserializer.java:71) ~[mysql-binlog-connector-java-0.13.0.jar:0.13.0]
	at com.github.shyiko.mysql.binlog.event.deserialization.UpdateRowsEventDataDeserializer.deserialize(UpdateRowsEventDataDeserializer.java:58) ~[mysql-binlog-connector-java-0.13.0.jar:0.13.0]
	at com.github.shyiko.mysql.binlog.event.deserialization.UpdateRowsEventDataDeserializer.deserialize(UpdateRowsEventDataDeserializer.java:33) ~[mysql-binlog-connector-java-0.13.0.jar:0.13.0]
	at com.github.shyiko.mysql.binlog.event.deserialization.EventDeserializer.deserializeEventData(EventDeserializer.java:210) ~[mysql-binlog-connector-java-0.13.0.jar:0.13.0]
	... 5 more
```
**This was the resolution, for the demo:**
1. Stop Maxwell's Daemon
1. Run the following from the MySQL command prompt, logged in as the DB super-user:
    ```
    mysql> PURGE BINARY LOGS BEFORE '2018-04-02 10:36:33';
    mysql> DROP DATABASE maxwell;
    ```
1. Restart Maxwell's Daemon


