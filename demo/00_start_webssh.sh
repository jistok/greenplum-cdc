#!/bin/bash

nohup ./.local/bin/wssh --sslport=8443 --certfile='./cdc-demo_hooliroof_com.crt' --keyfile='./server.key' >> webssh.log 2>&1 </dev/null &

