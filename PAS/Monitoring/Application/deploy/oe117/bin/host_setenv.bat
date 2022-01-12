@echo off

rem Get an IP address to use for identification of this server (from the default route).
for /f "usebackq tokens=4 delims= " %%f in (`route print ^| find " 0.0.0.0"`) do set PUBLIC_IP=%%f
