#!/bin/bash

consumer_group="test01"

$HOME/go-kafkacat --broker=localhost:9092 consume --group=$consumer_group maxwell --eof

