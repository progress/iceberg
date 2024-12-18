@echo off
rem Stop the database for the PAS instance.

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

echo Shutting down @DBNAME@ database.
%DLC%/bin/_mprshut -by %DBDIR%/@DBNAME@.db

exit /b 0
