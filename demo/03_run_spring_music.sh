#!/bin/bash

# Set up Cloud Foundry environment
export VCAP_APPLICATION=$( cat ./greenplum-cdc/VCAP_APPLICATION.json )
export VCAP_SERVICES=$( cat ./greenplum-cdc/VCAP_SERVICES.json )

java -jar ./spring-music/build/libs/spring-music-1.0.jar

