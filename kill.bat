@echo off
setlocal EnableDelayedExpansion

:: Resolve real script directory before re-launch
if "%~1"=="__INNER__" goto :main
cmd /k ""%~f0" __INNER__ "%~dp0""
exit /b

:main
set "SCRIPT_DIR=%~2"
if "!SCRIPT_DIR!"=="" set "SCRIPT_DIR=%~dp0"
cd /d "!SCRIPT_DIR!"
set "SCRIPT_DIR=%cd%\"

set "PID_FILE=%SCRIPT_DIR%proxy.pid"
set "LOG_FILE=%SCRIPT_DIR%proxy.log"

title Interface Proxy - Stop

echo.
echo  ============================================
echo   Interface-Bound Proxy - Stop
echo  ============================================
echo.

:: ----- Method 1: Use PID file -----
if not exist "%PID_FILE%" goto :no_pidfile

set /p PROXY_PID=<"%PID_FILE%"
echo  Found PID file. PID: !PROXY_PID!

:: Check if that PID is actually a running python process
tasklist /FI "PID eq !PROXY_PID!" 2>nul | findstr /i "python" >nul 2>&1
if errorlevel 1 goto :pid_not_running

echo  Killing proxy process (PID: !PROXY_PID!)...
taskkill /PID !PROXY_PID! /F >nul 2>&1
echo  Proxy stopped successfully.
del "%PID_FILE%" >nul 2>&1
goto :done

:pid_not_running
echo  Process !PROXY_PID! is not running (already stopped).
del "%PID_FILE%" >nul 2>&1
goto :done

:: ----- Method 2: No PID file, use PowerShell to find the process -----
:no_pidfile
echo  No PID file found. Searching for running proxy processes...
echo.

:: Use PowerShell to find python processes with interface_proxy in command line
set "FOUND=0"
powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*interface_proxy*' -and $_.Name -like '*python*' } | ForEach-Object { Write-Output $_.ProcessId }" > "%SCRIPT_DIR%_killpids.tmp" 2>nul

if not exist "%SCRIPT_DIR%_killpids.tmp" goto :search_done

for /f "tokens=*" %%p in ('type "%SCRIPT_DIR%_killpids.tmp"') do (
    set "FOUND=1"
    echo  Found proxy process: PID %%p
    echo  Killing...
    taskkill /PID %%p /F >nul 2>&1
    echo  Stopped.
)
del "%SCRIPT_DIR%_killpids.tmp" >nul 2>&1

:search_done
if "!FOUND!"=="0" (
    echo  No running proxy process found.
    echo  The proxy may already be stopped.
)

if exist "%PID_FILE%" del "%PID_FILE%" >nul 2>&1

:done
echo.
echo  ----------------------------------------
echo   Proxy stopped.
if exist "%LOG_FILE%" echo   Logs: %LOG_FILE%
echo  ----------------------------------------
echo.
pause
exit /b 0
