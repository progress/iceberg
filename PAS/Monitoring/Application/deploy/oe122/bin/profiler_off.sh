#!/bin/bash

echo "Setting up script for PID $1"

echo "" > jmxqueries/profiler_off_$1.qry

echo '{"O":"PASOE:type=OEManager,name=AgentManager", "M":["pushProfilerData", "'$1'", "", "0", ""]}' > jmxqueries/profiler_off_$1.qry

./oejmx.sh -R -O profiler_off_$1.out -Q jmxqueries/profiler_off_$1.qry
