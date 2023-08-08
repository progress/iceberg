#!/bin/bash

PULSE_TIME=20
APP_NAME=@APPNAME@
MONITOR_URI=http://@MONITOR@:@MONPORT@/web/pdo/monitor/intake/liveMetrics
#MONITOR_URI=file
HEALTH_URI=http://@MONITOR@:@MONPORT@/web/pdo/monitor/intake/liveHealth
HOST_IP=`ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p' | head -n 1`
NICKNAME=Metrics_`date +"%Y%m%d_%T"`

echo "Setting up script for PID $1"

echo "" > jmxqueries/pulse_on_$1.qry

# String before the first "|" may include any of "logmsgs,sessions,requests,calltrees,callstacks,ablobjs" or blank (for ALL).
#OPTIONS=logmsgs,sessions,requests,calltrees,callstacks,ablobjs
#OPTIONS=sessions,requests,calltrees,callstacks,ablobjs
#OPTIONS=sessions,requests,callstacks,ablobjs
OPTIONS=sessions,requests,calltrees,ablobjs
#OPTIONS=sessions,requests,ablobjs
#OPTIONS=sessions,requests

#
# The option "logmsgs" refers to the deferred logging feature:
# https://docs.progress.com/bundle/pas-for-openedge-admin/page/Use-deferred-logging-in-PAS-for-OpenEdge.html
#

# This is where the query is built and then executed via OEJMX
echo '{"O":"PASOE:type=OEManager,name=AgentManager", "M":["debugTest", "'$1'", "LiveDiag", "'$MONITOR_URI'", '$PULSE_TIME', "'$OPTIONS'|app='$APP_NAME'|host='$HOST_IP'|name='$NICKNAME'|health='$HEALTH_URI'"]}' > jmxqueries/pulse_on_$1.qry

./oejmx.sh -R -O pulse_on_$1.out -Q jmxqueries/pulse_on_$1.qry

