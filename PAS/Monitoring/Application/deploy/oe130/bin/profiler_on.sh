#!/bin/bash

MONITOR_IP=@MONITOR@
MONITOR_PORT=@MONPORT@
MONITOR_URI=http://$MONITOR_IP:$MONITOR_PORT/web/pdo/monitor/intake/liveProfile
APP_NAME=@APPNAME@
HOST_IP=`ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p' | head -n 1`
NICKNAME=Profiler_`date +"%Y%m%d_%T"`

echo "Setting up script for PID $1"

echo "" > jmxqueries/profiler_on_$1.qry

# This is where the query is built and then executed via OEJMX
echo '{"O":"PASOE:type=OEManager,name=AgentManager", "M":["pushProfilerData", "'$1'", "'$MONITOR_URI'", "-1", "{\"AdapterMask\":\"\",\"Coverage\":true,\"Statistics\":true,\"ProcList\":\"\",\"TestRunDescriptor\":\"app='$APP_NAME'|host='$HOST_IP'|name='$NICKNAME'\"}"]}' > jmxqueries/profiler_on_$1.qry

./oejmx.sh -R -O profiler_on_$1.out -Q jmxqueries/profiler_on_$1.qry
