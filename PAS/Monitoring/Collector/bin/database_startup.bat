@echo off
rem Start the database for the PAS instance.

set DBNAME=@DBNAME@
set DBPORT=@DBPORT@
rem Reserved for Enterprise RDBMS: -lruskips 500 -spin 20000
set DBOPTS=-bibufs 40 -B 64000 -L 102400 -Mm 32600 -Ma 10 -Mpb 30 -Mi 1 -Mn 30 -n 80

if not defined DLC (
    set DLC=@DLCHOME@
)

if not defined DBDIR (
    if not defined CATALINA_BASE (
        echo CATALINA_BASE is not defined, using static path.
        set DBDIR=@PASPATH@/db
    ) else (
        set DBDIR=%CATALINA_BASE%/db
    )
)

rem Check if the database is/isn't already started.
%DLC%/bin/_proutil %DBDIR%/%DBNAME%.db -C holder
if errorlevel 0 goto notinuse
goto end

:notinuse
rem Use of "start /min" is the only way to execute the database startup without blocking the rest of the PAS startup!
echo Starting database %DBNAME% on port %DBPORT%.
@start /min %DLC%/bin/_mprosrv %DBDIR%/%DBNAME%.db -H localhost -S %DBPORT% -N TCP %DBOPTS% -cpinternal @CODEPAGE@ -cpstream @CODEPAGE@
rem Pause for 4 seconds to allow database to start up.
timeout 4 > NUL
rem Check again if the database is/isn't already started.
%DLC%/bin/_proutil %DBDIR%/%DBNAME%.db -C holder
if errorlevel 0 goto dbprocs
goto starterror

:dbprocs
echo Starting watchdog and BIW/APW processes for %DBNAME%.
@start /min %DLC%/bin/_mprshut %DBDIR%/%DBNAME%.db -C watchdog -cpinternal @CODEPAGE@ -cpstream @CODEPAGE@
@start /min %DLC%/bin/_mprshut %DBDIR%/%DBNAME%.db -C biw -cpinternal @CODEPAGE@ -cpstream @CODEPAGE@
@start /min %DLC%/bin/_mprshut %DBDIR%/%DBNAME%.db -C apw -cpinternal @CODEPAGE@ -cpstream @CODEPAGE@
@start /min %DLC%/bin/_mprshut %DBDIR%/%DBNAME%.db -C apw -cpinternal @CODEPAGE@ -cpstream @CODEPAGE@
goto end

:starterror
echo Unable to start %DBNAME% database.
goto end

:end
exit /b 0
