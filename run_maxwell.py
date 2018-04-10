#!/usr/bin/env python

import os
import json

# $Id: run_maxwell.py,v 1.3 2018/04/10 16:05:04 mgoddard Exp mgoddard $

# Set up environment
os.environ['JAVA_HOME'] = '/home/vcap/app/.java-buildpack/open_jdk_jre'
os.environ['PATH'] = os.environ['JAVA_HOME'] + '/bin' + ':' + os.environ['PATH']

# Command line args to Maxwell
mysql_user = None
mysql_passwd = None
mysql_host = None
mysql_db = None
kafka_bootstrap_servers = None
kafka_topic = 'maxwell' # Default

# Check for bound services: MySQL, Kafka
vcap_str = os.environ.get('VCAP_SERVICES')
if vcap_str is None:
  raise Exception('VCAP_SERVICES not found in environment variables (necessary for credentials)')
vcap = json.loads(vcap_str)
for key in vcap:
  svc = vcap[key][0]
  tags = set(svc['tags'])
  if 'mysql' in tags:
    creds = svc['credentials']
    mysql_user = str(creds['username'])
    mysql_passwd = str(creds['password'])
    mysql_host = str(creds['hostname'])
    mysql_db = str(creds['name'])
  elif 'kafka' in tags:
    creds = svc['credentials']
    kafka_bootstrap_servers = str(creds['hostname'])
    if 'topicName' in creds:
      kafka_topic = str(creds['topicName'])

if mysql_user is None:
  raise Exception('No MySQL service instance bound')
if kafka_bootstrap_servers is None:
  raise Exception('No Kafka service instance bound')

# Exec the Maxwell startup script, with the required arguments
os.execlp('./bin/maxwell', '--output_ddl=true', '--user=' + mysql_user, '--password=' + mysql_passwd,
  '--host=' + mysql_host, '--schema_database=' + mysql_db, '--producer=kafka',
  '--kafka.bootstrap.servers=' + kafka_bootstrap_servers, '--kafka_topic=' + kafka_topic)

