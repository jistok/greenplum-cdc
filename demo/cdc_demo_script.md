# CDC Demo Script

## Open the following links, one per browser tab

**NOTE:**

* So far, this has been tested using Chrome, on a Mac.
* The hostname in these links, `cdc-demo.hooliroof.com`, varies per installation of the demo.
* The value after `password=` parameter is the base 64 encoding of the VM user's password.  Based
  on the discussion in README.md, you derive this value using this approach:
  ```
  $ echo -n "NEW_PASSWORD" | base64
  ```

1. [Start Maxwell's Daemon](https://cdc-demo.hooliroof.com:8443/?title=Maxwell&command=./01_run_maxwell.sh;exit&hostname=localhost&username=ubuntu&password=WUdRTEZJREVSWFNSRFlESkVaTU8=&term=xterm-256color)
1. [RabbitMQ to Greenplum](https://cdc-demo.hooliroof.com:8443/?title=RMQ to GPDB&command=./02_rmq_to_gpdb.sh;exit&hostname=localhost&username=ubuntu&password=WUdRTEZJREVSWFNSRFlESkVaTU8=&term=xterm-256color)
1. [Run Spring Music](https://cdc-demo.hooliroof.com:8443/?title=Run Spring Music&command=./03_run_spring_music.sh;exit&hostname=localhost&username=ubuntu&password=WUdRTEZJREVSWFNSRFlESkVaTU8=&term=xterm-256color)
1. [Poll the MySQL DB](https://cdc-demo.hooliroof.com:8443/?title=MySQL Poll&command=./04_mysql_poll.sh;exit&hostname=localhost&username=ubuntu&password=WUdRTEZJREVSWFNSRFlESkVaTU8=&term=xterm-256color)
1. [Poll Greenplum DB](https://cdc-demo.hooliroof.com:8443/?title=GPDB Poll&command=./05_gpdb_poll.sh;exit&hostname=localhost&username=ubuntu&password=WUdRTEZJREVSWFNSRFlESkVaTU8=&term=xterm-256color)
1. [Run a MySQL client](https://cdc-demo.hooliroof.com:8443/?title=MySQL Client&command=./06_mysql_client.sh;exit&hostname=localhost&username=ubuntu&password=WUdRTEZJREVSWFNSRFlESkVaTU8=&term=xterm-256color)
1. [Spring Music Web UI](http://cdc-demo.hooliroof.com:8080/)


