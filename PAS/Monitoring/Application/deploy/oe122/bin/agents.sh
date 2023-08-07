#!/bin/bash

ABL_APP_NAME=@APPNAME@
echo '{"O":"PASOE:type=OEManager,name=AgentManager", "M":["getAgents", "'$ABL_APP_NAME'"]}' > jmxqueries/agents.qry

echo "" > agents.out
./oejmx.sh -R -O agents.out -Q jmxqueries/agents.qry
cat agents.out | grep -o '"pid":"[0-9]*"'
