@echo off

set ABL_APP_NAME=@APPNAME@
echo {"O":"PASOE:type=OEManager,name=AgentManager", "M":["getAgents", "%ABL_APP_NAME%"]} > jmxqueries/agents.qry

break > agents.out
echo "Querying for agents, check agents.out for available PID's..."
./oejmx.bat -R -O agents.out -Q jmxqueries/agents.qry

exit /b 0

