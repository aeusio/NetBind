@echo off
setlocal EnableDelayedExpansion

:: Ensure the window stays open even if something crashes.
:: Pass the real script directory as arg so it survives the cmd /k re-launch.
if "%~1"=="__INNER__" goto :main
cmd /k ""%~f0" __INNER__ "%~dp0""
exit /b

:main
:: %~2 is the real directory passed from the outer wrapper
set "SCRIPT_DIR=%~2"
if "!SCRIPT_DIR!"=="" set "SCRIPT_DIR=%~dp0"
cd /d "!SCRIPT_DIR!"
set "SCRIPT_DIR=%cd%\"

title Interface Proxy - Setup and Launcher

set "VENV_DIR=%SCRIPT_DIR%venv"
set "PORTABLE_DIR=%SCRIPT_DIR%python"
set "TEMP_DIR=%SCRIPT_DIR%temp_setup"

set "PYTHON_VERSION=3.12.4"
set "PYTHON_ZIP=python-%PYTHON_VERSION%-embed-amd64.zip"
set "PYTHON_ZIP_URL=https://www.python.org/ftp/python/%PYTHON_VERSION%/%PYTHON_ZIP%"
set "GET_PIP_URL=https://bootstrap.pypa.io/get-pip.py"

echo.
echo  ========================================================
echo    Interface-Bound Proxy - Setup and Launcher
echo  ========================================================
echo.
echo  Working directory: %SCRIPT_DIR%
echo.

:: -----------------------------------------------------------------
::  STEP 1: Check for a working Python
:: -----------------------------------------------------------------
echo  [1/5] Checking for Python...

set "PYTHON_CMD="
set "PY_VER="

:: Priority 1: Our own portable Python (from a previous setup run)
if exist "%PORTABLE_DIR%\python.exe" (
    echo        Testing portable Python...
    call :test_python "%PORTABLE_DIR%\python.exe"
    if defined PYTHON_CMD (
        echo        Found portable Python in project folder.
        goto :found_python
    )
)

:: Priority 2: Virtual env from previous run
if exist "%VENV_DIR%\Scripts\python.exe" (
    echo        Testing venv Python...
    call :test_python "%VENV_DIR%\Scripts\python.exe"
    if defined PYTHON_CMD (
        echo        Found in virtual environment.
        goto :found_python
    )
)

:: Priority 3: System-installed Python in known directories
call :scan_known_dirs
if defined PYTHON_CMD goto :found_python

:: Priority 4: py launcher
where py >nul 2>&1
if not errorlevel 1 (
    echo        Testing py launcher...
    call :test_python_bare py -3
    if defined PYTHON_CMD (
        echo        Found via py launcher.
        goto :found_python
    )
)

:: Priority 5: PATH (checked last to avoid Windows Store stub)
where python >nul 2>&1
if not errorlevel 1 (
    echo        Testing python on PATH...
    call :test_python_bare python
    if defined PYTHON_CMD (
        echo        Found python on PATH.
        goto :found_python
    )
)

:: Nothing found
echo        No working Python found.
goto :install_portable

:: -----------------------------------------------------------------
::  STEP 1b: Verify version is 3.10+
:: -----------------------------------------------------------------
:found_python
echo        Using: !PYTHON_CMD!
echo        Version: !PY_VER!

for /f "tokens=1,2 delims=." %%a in ("!PY_VER!") do (
    set "PY_MAJOR=%%a"
    set "PY_MINOR=%%b"
)

set "VERSION_OK=0"
if !PY_MAJOR! GEQ 4 set "VERSION_OK=1"
if !PY_MAJOR! EQU 3 if !PY_MINOR! GEQ 10 set "VERSION_OK=1"

if "!VERSION_OK!"=="1" (
    echo        Version OK.
    echo.
    goto :ensure_pip
) else (
    echo        Python !PY_VER! is too old. Need 3.10+. Will install portable.
    goto :install_portable
)

:: -----------------------------------------------------------------
::  STEP 2: Download and set up portable Python (embeddable zip)
:: -----------------------------------------------------------------
:install_portable
echo.
echo  [2/5] Setting up portable Python %PYTHON_VERSION%...
echo        No installer needed. No admin required.
echo.

if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%"
if not exist "%PORTABLE_DIR%" mkdir "%PORTABLE_DIR%"

:: --- Download embeddable zip ---
if exist "%TEMP_DIR%\%PYTHON_ZIP%" (
    echo        Zip already downloaded.
) else (
    echo        Downloading Python embeddable zip...
    echo        URL: %PYTHON_ZIP_URL%
    powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $ProgressPreference = 'SilentlyContinue'; try { Invoke-WebRequest -Uri '%PYTHON_ZIP_URL%' -OutFile '%TEMP_DIR%\%PYTHON_ZIP%' -UseBasicParsing; Write-Host '        Download complete.' } catch { Write-Host ('        Error: ' + $_.Exception.Message); exit 1 }"
)

if not exist "%TEMP_DIR%\%PYTHON_ZIP%" (
    echo.
    echo  !! ERROR: Failed to download Python zip.
    echo  Check your internet connection and try again.
    echo.
    pause
    exit /b 1
)

:: --- Extract zip ---
echo        Extracting to %PORTABLE_DIR% ...
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Expand-Archive -Path '%TEMP_DIR%\%PYTHON_ZIP%' -DestinationPath '%PORTABLE_DIR%' -Force; Write-Host '        Extracted.' } catch { Write-Host ('        Error: ' + $_.Exception.Message); exit 1 }"

if not exist "%PORTABLE_DIR%\python.exe" (
    echo.
    echo  !! ERROR: Extraction failed. python.exe not found.
    echo.
    pause
    exit /b 1
)

:: --- Enable site-packages (required for pip to work) ---
echo        Enabling site-packages...
set "PTH_FILE="
for %%F in ("%PORTABLE_DIR%\python*._pth") do set "PTH_FILE=%%F"

if defined PTH_FILE (
    echo        Editing: !PTH_FILE!
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$f = '!PTH_FILE!'; (Get-Content $f) -replace '^#import site','import site' | Set-Content $f; Write-Host '        site-packages enabled.'"
) else (
    echo        WARNING: No ._pth file found. pip may not work.
)

:: --- Download get-pip.py ---
if exist "%TEMP_DIR%\get-pip.py" (
    echo        get-pip.py already downloaded.
) else (
    echo        Downloading get-pip.py...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $ProgressPreference = 'SilentlyContinue'; try { Invoke-WebRequest -Uri '%GET_PIP_URL%' -OutFile '%TEMP_DIR%\get-pip.py' -UseBasicParsing; Write-Host '        Downloaded.' } catch { Write-Host ('        Error: ' + $_.Exception.Message); exit 1 }"
)

if not exist "%TEMP_DIR%\get-pip.py" (
    echo.
    echo  !! ERROR: Failed to download get-pip.py
    echo.
    pause
    exit /b 1
)

:: --- Install pip ---
echo        Installing pip...
"%PORTABLE_DIR%\python.exe" "%TEMP_DIR%\get-pip.py" --no-warn-script-location
if errorlevel 1 (
    echo.
    echo  !! ERROR: pip installation failed.
    echo.
    pause
    exit /b 1
)

:: --- Set PYTHON_CMD directly (we know it works because pip just ran) ---
set "PYTHON_CMD=%PORTABLE_DIR%\python.exe"

:: Get version for display
set "PY_VER="
"%PORTABLE_DIR%\python.exe" -c "import sys; print(sys.version.split()[0])" > "%TEMP_DIR%\_pyver.txt" 2>nul
if exist "%TEMP_DIR%\_pyver.txt" (
    set /p PY_VER=<"%TEMP_DIR%\_pyver.txt"
    del "%TEMP_DIR%\_pyver.txt" >nul 2>&1
)

:: Clean up temp files
if exist "%TEMP_DIR%\%PYTHON_ZIP%" del /q "%TEMP_DIR%\%PYTHON_ZIP%" >nul 2>&1
if exist "%TEMP_DIR%\get-pip.py" del /q "%TEMP_DIR%\get-pip.py" >nul 2>&1
if exist "%TEMP_DIR%" rmdir /q "%TEMP_DIR%" >nul 2>&1

echo.
echo        Portable Python ready!
echo        Location: !PYTHON_CMD!
echo        Version:  !PY_VER!
echo.

goto :ensure_pip

:: -----------------------------------------------------------------
::  STEP 3: Ensure pip is available and up to date
:: -----------------------------------------------------------------
:ensure_pip
echo  [3/5] Checking pip...

"!PYTHON_CMD!" -m pip --version >nul 2>&1
if errorlevel 1 (
    echo        pip not found. Installing...
    if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%"
    powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri '%GET_PIP_URL%' -OutFile '%TEMP_DIR%\get-pip.py' -UseBasicParsing"
    "!PYTHON_CMD!" "%TEMP_DIR%\get-pip.py" --no-warn-script-location
    if exist "%TEMP_DIR%\get-pip.py" del /q "%TEMP_DIR%\get-pip.py" >nul 2>&1
    if exist "%TEMP_DIR%" rmdir /q "%TEMP_DIR%" >nul 2>&1
)

"!PYTHON_CMD!" -m pip install --upgrade pip --quiet --no-warn-script-location 2>nul
echo        pip is ready.
echo.

:: -----------------------------------------------------------------
::  STEP 4: Install dependencies
:: -----------------------------------------------------------------
echo  [4/5] Installing dependencies...

"!PYTHON_CMD!" -m pip install -r "%SCRIPT_DIR%requirements.txt" --quiet --no-warn-script-location
if errorlevel 1 (
    echo        Retrying with verbose output...
    "!PYTHON_CMD!" -m pip install -r "%SCRIPT_DIR%requirements.txt" --no-warn-script-location
    if errorlevel 1 (
        echo.
        echo  !! ERROR: Failed to install dependencies.
        echo.
        pause
        exit /b 1
    )
)

echo        Dependencies installed.
echo.

:: -----------------------------------------------------------------
::  STEP 5: Verify everything works
:: -----------------------------------------------------------------
echo  [5/5] Verifying installation...

"!PYTHON_CMD!" -c "import psutil; import asyncio; import socket; print('        All modules loaded OK.')"
if errorlevel 1 (
    echo.
    echo  !! ERROR: Module verification failed.
    echo  Try: "!PYTHON_CMD!" -m pip install psutil
    echo.
    pause
    exit /b 1
)

set "PID_FILE=%SCRIPT_DIR%proxy.pid"
set "LOG_FILE=%SCRIPT_DIR%proxy.log"

echo.
echo  ========================================================
echo    Setup complete! Select interface to start proxy...
echo  ========================================================
echo.

:: ----- Show interfaces and let user pick -----
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
    pause
    exit /b 1
)

echo.
set "CHOICE=0"
set /p CHOICE="  Select interface number: "

set "BIND_IP="
if !CHOICE! GEQ 1 if !CHOICE! LEQ !IFACE_COUNT! (
    set "BIND_IP=!IFACE_IP_%CHOICE%!"
)

if not defined BIND_IP (
    echo  Invalid choice.
    pause
    exit /b 1
)

echo.
echo  Starting proxy on interface !BIND_IP! (detached)...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '!PYTHON_CMD!' -ArgumentList '\"%SCRIPT_DIR%interface_proxy.py\" --bind !BIND_IP! --logfile \"%LOG_FILE%\" --pidfile \"%PID_FILE%\"' -WindowStyle Hidden"

timeout /t 3 /nobreak >nul

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
::  SUBROUTINE: Scan known system Python directories
:: =================================================================
:scan_known_dirs
set "PYTHON_CMD="
for %%D in (
    "%LOCALAPPDATA%\Programs\Python\Python313"
    "%LOCALAPPDATA%\Programs\Python\Python312"
    "%LOCALAPPDATA%\Programs\Python\Python311"
    "%LOCALAPPDATA%\Programs\Python\Python310"
    "C:\Python313"
    "C:\Python312"
    "C:\Python311"
    "C:\Python310"
    "%ProgramFiles%\Python313"
    "%ProgramFiles%\Python312"
    "%ProgramFiles%\Python311"
    "%ProgramFiles%\Python310"
) do (
    if not defined PYTHON_CMD (
        if exist "%%~D\python.exe" (
            echo        Checking %%~D ...
            call :test_python "%%~D\python.exe"
        )
    )
)
goto :eof


:: =================================================================
::  SUBROUTINE: Test a python.exe given as a full path
::
::  Instead of using fragile "for /f" to capture output inline,
::  we write the version to a temp file and read it back.
:: =================================================================
:test_python
set "PYTHON_CMD="
set "PY_VER="
set "_TP_EXE=%~1"

if not exist "%_TP_EXE%" goto :eof

:: Write version to a temp file
"%_TP_EXE%" -c "import sys; print(sys.version.split()[0])" > "%SCRIPT_DIR%_pytest.tmp" 2>nul

if not exist "%SCRIPT_DIR%_pytest.tmp" goto :eof

:: Read the first line
set "_TP_VER="
set /p _TP_VER=<"%SCRIPT_DIR%_pytest.tmp"
del "%SCRIPT_DIR%_pytest.tmp" >nul 2>&1

if not defined _TP_VER goto :eof

:: Verify it looks like a version (starts with a digit)
echo !_TP_VER! | findstr /r "^[0-9]" >nul 2>&1
if errorlevel 1 goto :eof

set "PYTHON_CMD=%_TP_EXE%"
set "PY_VER=!_TP_VER!"
goto :eof


:: =================================================================
::  SUBROUTINE: Test a bare command like "python" or "py -3"
::  (not a file path, so we cannot use "if exist" or quote it)
:: =================================================================
:test_python_bare
set "PYTHON_CMD="
set "PY_VER="
set "_TP_CMD=%*"

:: Write version to a temp file
!_TP_CMD! -c "import sys; print(sys.version.split()[0])" > "%SCRIPT_DIR%_pytest.tmp" 2>nul

if not exist "%SCRIPT_DIR%_pytest.tmp" goto :eof

set "_TP_VER="
set /p _TP_VER=<"%SCRIPT_DIR%_pytest.tmp"
del "%SCRIPT_DIR%_pytest.tmp" >nul 2>&1

if not defined _TP_VER goto :eof

echo !_TP_VER! | findstr /r "^[0-9]" >nul 2>&1
if errorlevel 1 goto :eof

set "PYTHON_CMD=!_TP_CMD!"
set "PY_VER=!_TP_VER!"
goto :eof
