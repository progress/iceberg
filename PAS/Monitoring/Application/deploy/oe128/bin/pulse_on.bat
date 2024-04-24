@echo off

set PULSE_TIME=20
set APP_NAME=@APPNAME@
set MONITOR_URI=http://@MONITOR@:@MONPORT@/web/pdo/monitor/intake/liveMetrics
rem set MONITOR_URI=file
set HEALTH_URI=http://@MONITOR@:@MONPORT@/web/pdo/monitor/intake/liveHealth

rem Get an IP address to use for identification of this server (from the default route).
for /f "usebackq tokens=4 delims= " %%f in (`route print ^| find " 0.0.0.0"`) do set HOST_IP=%%f

for /f "tokens=2-4 delims=/ " %%a in ('date /t') do (set mydate=%%c-%%a-%%b)
for /f "tokens=1-2 delims=/:" %%a in ("%TIME%") do (set mytime=%%a%%b)
set NICKNAME=Metrics_%mydate%-%mytime%

echo "Setting up script for PID %1"

break > jmxqueries/pulse_on_%1.qry

rem String before the first "|" may include any of "logmsgs,sessions,requests,calltrees,callstacks,ablobjs" or blank (for ALL).
rem set OPTIONS=logmsgs,sessions,requests,calltrees,callstacks,ablobjs
rem set OPTIONS=sessions,requests,calltrees,callstacks,ablobjs
rem set OPTIONS=sessions,requests,callstacks,ablobjs
set OPTIONS=sessions,requests,calltrees,ablobjs
rem set OPTIONS=sessions,requests,ablobjs
rem set OPTIONS=sessions,requests

rem The option "logmsgs" refers to the deferred logging feature:
rem https://docs.progress.com/bundle/pas-for-openedge-admin/page/Use-deferred-logging-in-PAS-for-OpenEdge.html

rem This is where the query is built and then executed via OEJMX
echo {"O":"PASOE:type=OEManager,name=AgentManager", "M":["debugTest", "%1", "LiveDiag", "%MONITOR_URI%", %PULSE_TIME%, "%OPTIONS%|app=%APP_NAME%|host=%HOST_IP%|name=%NICKNAME%|health=%HEALTH_URI%"]} > jmxqueries/pulse_on_%1.qry

./oejmx.bat -R -O pulse_on_%1.out -Q jmxqueries/pulse_on_%1.qry

exit /b 0

