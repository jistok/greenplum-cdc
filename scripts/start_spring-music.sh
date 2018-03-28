#!/bin/bash

dir="./spring-music"

export VCAP_APPLICATION=$( cat $dir/VCAP_APPLICATION.json )
export VCAP_SERVICES=$( cat $dir/VCAP_SERVICES_MYSQL.json )

java -jar $dir/build/libs/spring-music.jar

