@echo off
REM OpenEdge - OEManager CLI Utility

REM Utility must be run with DLC environment variable set
if exist "%DLC%"\ant goto BIN
   echo.
   echo Progress DLC environment variable may not be set correctly.
   echo Set DLC variable to Progress installation directory.
   echo.
   pause
   goto END

:BIN
if "%ANTSCRIPT%"=="" set ANTSCRIPT="%DLC%"\ant\bin\ant.bat
if exist "%ANTSCRIPT%" goto START
   cls
   echo AppServer %0 Messages:
   echo.
   echo The OpenEdge Apache Ant launch script could not be found.
   echo.
   echo Progress DLC environment variable may not be set correctly.
   echo Set DLC variable to Progress installation directory.
   echo.
   echo Progress DLC setting: %DLC%
   echo Script not found: %ANTSCRIPT%
   echo.
   pause
   goto END

:START
REM Set JAVA_HOME by calling java_env
if exist "%DLC%\bin\java_env.bat" (
    call "%DLC%\bin\java_env.bat"
)

REM Use the PowerShell utility to execute the Ant utility with all given parameters
PowerShell.exe -executionpolicy bypass -File "%~dp0\oemanager.ps1" %*

goto END

:END
