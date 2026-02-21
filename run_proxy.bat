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

title Interface Proxy - Launcher

set "PORTABLE_DIR=%SCRIPT_DIR%python"
set "VENV_DIR=%SCRIPT_DIR%venv"
set "PID_FILE=%SCRIPT_DIR%proxy.pid"
set "LOG_FILE=%SCRIPT_DIR%proxy.log"

echo.
echo  ============================================
echo   Interface-Bound Proxy Server
echo  ============================================
echo.

:: ----- Check if proxy is already running -----
if exist "%PID_FILE%" (
    set /p OLD_PID=<"%PID_FILE%"
    tasklist /FI "PID eq !OLD_PID!" 2>nul | findstr /i "python" >nul 2>&1
    if not errorlevel 1 (
        echo  Proxy is already running (PID: !OLD_PID!).
        echo  Use kill.bat to stop it first.
        echo.
        pause
        exit /b 0
    ) else (
        echo  Stale PID file found. Cleaning up...
        del "%PID_FILE%" >nul 2>&1
    )
)

:: ----- Find Python -----
set "PYTHON_CMD="

if exist "%PORTABLE_DIR%\python.exe" (
    call :test_python "%PORTABLE_DIR%\python.exe"
    if defined PYTHON_CMD goto :found
)

if exist "%VENV_DIR%\Scripts\python.exe" (
    call :test_python "%VENV_DIR%\Scripts\python.exe"
    if defined PYTHON_CMD goto :found
)

where py >nul 2>&1
if not errorlevel 1 (
    call :test_python_bare py -3
    if defined PYTHON_CMD goto :found
)

where python >nul 2>&1
if not errorlevel 1 (
    call :test_python_bare python
    if defined PYTHON_CMD goto :found
)

echo  ERROR: No working Python found. Please run setup.bat first.
echo.
pause
exit /b 1

:found
:: ----- Verify dependencies -----
"!PYTHON_CMD!" -c "import psutil" >nul 2>&1
if not errorlevel 1 goto :select_iface

echo.
echo  Dependencies not installed. Please run setup.bat first.
echo.
pause
exit /b 1

:: ----- Show interfaces and let user pick -----
:select_iface
echo  Detecting network interfaces...
echo.

:: Get interface list from Python
"!PYTHON_CMD!" "%SCRIPT_DIR%interface_proxy.py" --list-interfaces > "%SCRIPT_DIR%_ifaces.tmp" 2>nul

set "IFACE_COUNT=0"
for /f "tokens=1,* delims=	" %%a in ('type "%SCRIPT_DIR%_ifaces.tmp"') do (
    set /a IFACE_COUNT+=1
    set "IFACE_IP_!IFACE_COUNT!=%%a"
    set "IFACE_NAME_!IFACE_COUNT!=%%b"
    echo    [!IFACE_COUNT!]  %%a   ^(%%b^)
)
del "%SCRIPT_DIR%_ifaces.tmp" >nul 2>&1

if !IFACE_COUNT! EQU 0 (
    echo  ERROR: No network interfaces found.
    echo.
    pause
    exit /b 1
)

echo.
set "CHOICE=0"
set /p CHOICE="  Select interface number: "

:: Validate choice
set "BIND_IP="
if !CHOICE! GEQ 1 if !CHOICE! LEQ !IFACE_COUNT! (
    set "BIND_IP=!IFACE_IP_%CHOICE%!"
)

if not defined BIND_IP (
    echo  Invalid choice.
    echo.
    pause
    exit /b 1
)

echo.
echo  Starting proxy on interface !BIND_IP! ...
echo  Logs: %LOG_FILE%
echo.

:: ----- Launch as a fully independent process (survives terminal close) -----
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '!PYTHON_CMD!' -ArgumentList '\"%SCRIPT_DIR%interface_proxy.py\" --bind !BIND_IP! --logfile \"%LOG_FILE%\" --pidfile \"%PID_FILE%\"' -WindowStyle Hidden"

:: Wait for it to start and write the PID file
timeout /t 3 /nobreak >nul

:: Verify it started
if exist "%PID_FILE%" (
    set /p NEW_PID=<"%PID_FILE%"
    echo  ========================================
    echo   Proxy is running!
    echo  ========================================
    echo.
    echo   PID:       !NEW_PID!
    echo   Proxy:     127.0.0.1:8118
    echo   Interface: !BIND_IP!
    echo   Logs:      %LOG_FILE%
    echo.
    echo   Set your browser proxy to 127.0.0.1:8118
    echo   Run kill.bat to stop the proxy.
    echo.
) else (
    echo  ERROR: Proxy failed to start. Check %LOG_FILE% for details.
    echo.
)

pause
exit /b 0


:: =================================================================
:test_python
set "PYTHON_CMD="
set "_TP_EXE=%~1"
if not exist "%_TP_EXE%" goto :eof
"%_TP_EXE%" -c "import sys; print(sys.version.split()[0])" > "%SCRIPT_DIR%_pytest.tmp" 2>nul
if not exist "%SCRIPT_DIR%_pytest.tmp" goto :eof
set /p _TP_VER=<"%SCRIPT_DIR%_pytest.tmp"
del "%SCRIPT_DIR%_pytest.tmp" >nul 2>&1
if not defined _TP_VER goto :eof
echo !_TP_VER! | findstr /r "^[0-9]" >nul 2>&1
if errorlevel 1 goto :eof
set "PYTHON_CMD=%_TP_EXE%"
goto :eof

:test_python_bare
set "PYTHON_CMD="
set "_TP_CMD=%*"
!_TP_CMD! -c "import sys; print(sys.version.split()[0])" > "%SCRIPT_DIR%_pytest.tmp" 2>nul
if not exist "%SCRIPT_DIR%_pytest.tmp" goto :eof
set /p _TP_VER=<"%SCRIPT_DIR%_pytest.tmp"
del "%SCRIPT_DIR%_pytest.tmp" >nul 2>&1
if not defined _TP_VER goto :eof
echo !_TP_VER! | findstr /r "^[0-9]" >nul 2>&1
if errorlevel 1 goto :eof
set "PYTHON_CMD=!_TP_CMD!"
goto :eof
