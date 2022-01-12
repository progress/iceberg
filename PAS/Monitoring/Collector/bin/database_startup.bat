@echo off
rem Start the database for the PAS instance.

set DBPORT=@DBPORT@
set DBOPTS=-bibufs 40 -B 64000 -L 102400 -lruskips 500 -Mm 32600 -Ma 10 -Mpb 30 -Mi 1 -Mn 30 -n 360 -spin 20000

if not defined DLC (
    set DLC=@DLCHOME@
)

if not defined DBDIR (
    set DBDIR=%CATALINA_BASE%/db
)

rem Check if the database is/isn't already started.
%DLC%/bin/_proutil %DBDIR%/@DBNAME@.db -C holder
if errorlevel 0 goto notinuse
goto end

:notinuse
rem Use of "start /min" is the only way to execute the database startup without blocking the rest of the PAS startup!
@start /min %DLC%/bin/_mprosrv %DBDIR%/@DBNAME@.db -H localhost -S %DBPORT% -N TCP %DBOPTS% -cpinternal @CODEPAGE@ -cpstream @CODEPAGE@
timeout 2 > NUL
@start /min %DLC%/bin/_mprshut %DBDIR%/@DBNAME@.db -C biw -cpinternal @CODEPAGE@ -cpstream @CODEPAGE@
@start /min %DLC%/bin/_mprshut %DBDIR%/@DBNAME@.db -C apw -cpinternal @CODEPAGE@ -cpstream @CODEPAGE@
@start /min %DLC%/bin/_mprshut %DBDIR%/@DBNAME@.db -C apw -cpinternal @CODEPAGE@ -cpstream @CODEPAGE@
goto end

:end

exit /b 0
