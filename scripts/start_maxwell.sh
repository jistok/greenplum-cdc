#!/bin/bash

$HOME/maxwell-1.13.2/bin/maxwell --output_ddl=true --user='maxwell' --password='maxwell' --host='127.0.0.1' --producer=kafka --kafka.bootstrap.servers=localhost:9092

