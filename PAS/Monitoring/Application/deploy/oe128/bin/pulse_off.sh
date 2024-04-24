#!/bin/bash

PULSE_TIME=0

echo "Setting up script for PID $1"

echo "" > jmxqueries/pulse_off_$1.qry

echo '{"O":"PASOE:type=OEManager,name=AgentManager", "M":["debugTest", "'$1'", "LiveDiag", "", '$PULSE_TIME', ""]}' > jmxqueries/pulse_off_$1.qry

./oejmx.sh -R -O pulse_off_$1.out -Q jmxqueries/pulse_off_$1.qry
