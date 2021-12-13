@echo off
rem Stop the database for the PAS instance.

if not defined DLC (
    set DLC=@DLCHOME@
)

if not defined DBDIR (
    set DBDIR=%CATALINA_BASE%/db
)

%DLC%/bin/_mprshut -by %DBDIR%/@DBNAME@.db

exit /b 0
