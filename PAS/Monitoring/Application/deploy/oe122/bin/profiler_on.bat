@echo off

set MONITOR_IP=@MONITOR@
set MONITOR_PORT=@MONPORT@
set MONITOR_URI=http://%MONITOR_IP%:%MONITOR_PORT%/web/pdo/monitor/intake/liveProfile
set APP_NAME=@APPNAME@

rem Get a non-loopback address to use for identification of this server.
for /f "usebackq tokens=4 delims= " %%f in (`route print ^| find " 0.0.0.0"`) do set HOST_IP=%%f

for /f "tokens=2-4 delims=/ " %%a in ('date /t') do (set mydate=%%c-%%a-%%b)
for /f "tokens=1-2 delims=/:" %%a in ("%TIME%") do (set mytime=%%a%%b)
set NICKNAME=Profiler_%mydate%-%mytime%

echo "Setting up script for PID %1"

break > jmxqueries/profiler_on_%1.qry

rem This is where the query is built and then executed via OEJMX
echo {"O":"PASOE:type=OEManager,name=AgentManager", "M":["pushProfilerData", "%1", "%MONITOR_URI%", "-1", "{\"AdapterMask\":\"\",\"Coverage\":true,\"Statistics\":true,\"ProcList\":\"\",\"TestRunDescriptor\":\"app=%APP_NAME%|host=%HOST_IP%|name=%NICKNAME%\"}"]} > jmxqueries/profiler_on_%1.qry

./oejmx.bat -R -O profiler_on_%1.out -Q jmxqueries/profiler_on_%1.qry

exit /b 0

