REM install-print-monitor.bat
@echo off
REM Print Monitor Windows Installer v1.0

echo ========================================
echo    Print Monitor Installer v1.0
echo ========================================
echo.

REM Check if running as Administrator
net session >nul 2>&1
if %errorLevel% == 0 (
    echo [OK] Running as Administrator
) else (
    echo [ERROR] Please run this script as Administrator
    echo Right-click and select "Run as administrator"
    pause
    exit /b 1
)

REM Set variables
set INSTALL_DIR=C:\PrintMonitor
set SERVICE_NAME=Print Monitor Service

echo [INFO] Installing Print Monitor Service
echo [INFO] Install Directory: %INSTALL_DIR%
echo.

REM Stop service if already running
echo [STEP 1] Stopping existing service...
sc query "%SERVICE_NAME%" >nul 2>&1
if %errorLevel% == 0 (
    echo Service exists, stopping...
    sc stop "%SERVICE_NAME%"
    timeout /t 3 /nobreak >nul
)

REM Create installation directory
echo [STEP 2] Creating installation directory...
if not exist "%INSTALL_DIR%" (
    mkdir "%INSTALL_DIR%"
    echo Created directory: %INSTALL_DIR%
) else (
    echo Directory already exists: %INSTALL_DIR%
)

REM Create logs directory
if not exist "%INSTALL_DIR%\logs" (
    mkdir "%INSTALL_DIR%\logs"
    echo Created logs directory
)

REM Copy files
echo [STEP 3] Copying program files...
copy /Y "PrintListener.exe" "%INSTALL_DIR%\"
copy /Y "appsettings.json" "%INSTALL_DIR%\"
copy /Y "*.dll" "%INSTALL_DIR%\" 2>nul
copy /Y "*.deps.json" "%INSTALL_DIR%\" 2>nul
copy /Y "*.runtimeconfig.json" "%INSTALL_DIR%\" 2>nul

if %errorLevel% == 0 (
    echo [OK] Files copied successfully
) else (
    echo [ERROR] Failed to copy files
    pause
    exit /b 1
)

REM Install service
echo [STEP 4] Installing Windows service...
sc delete "%SERVICE_NAME%" >nul 2>&1
sc create "%SERVICE_NAME%" binPath="%INSTALL_DIR%\PrintListener.exe" start=auto DisplayName="Print Monitor Service"
if %errorLevel% == 0 (
    echo [OK] Service installed successfully
) else (
    echo [ERROR] Failed to install service
    pause
    exit /b 1
)

REM Set service description
sc description "%SERVICE_NAME%" "Monitors print jobs and sends data to Print Monitor dashboard"

REM Set service recovery options
sc failure "%SERVICE_NAME%" reset=300 actions=restart/60000/restart/60000/restart/60000

REM Start service
echo [STEP 5] Starting service...
sc start "%SERVICE_NAME%"
if %errorLevel% == 0 (
    echo [OK] Service started successfully
) else (
    echo [WARNING] Service failed to start - check logs
)

REM Wait a moment and check service status
timeout /t 3 /nobreak >nul
sc query "%SERVICE_NAME%" | find "RUNNING" >nul
if %errorLevel% == 0 (
    echo [OK] Service is running
) else (
    echo [WARNING] Service may not be running properly
    echo Check Event Viewer or service logs
)

REM Create desktop shortcut for logs
echo [STEP 6] Creating shortcuts...
powershell -Command "$WshShell = New-Object -comObject WScript.Shell; $Shortcut = $WshShell.CreateShortcut('%USERPROFILE%\Desktop\Print Monitor Logs.lnk'); $Shortcut.TargetPath = '%INSTALL_DIR%\logs'; $Shortcut.Save()"

REM Create uninstaller
echo [STEP 7] Creating uninstaller...
(
echo @echo off
echo echo Uninstalling Print Monitor Service...
echo sc stop "%SERVICE_NAME%"
echo sc delete "%SERVICE_NAME%"
echo rmdir /s /q "%INSTALL_DIR%"
echo echo Service uninstalled successfully!
echo pause
) > "%INSTALL_DIR%\uninstall.bat"

echo.
echo ========================================
echo         Installation Complete!
echo ========================================
echo.
echo Service Name: %SERVICE_NAME%
echo Install Location: %INSTALL_DIR%
echo.
echo To check service status:
echo   - Open Services.msc
echo   - Look for "Print Monitor Service"
echo.
echo To view logs:
echo   - Check desktop shortcut "Print Monitor Logs"
echo   - Or browse to %INSTALL_DIR%\logs
echo.
echo To uninstall:
echo   - Run %INSTALL_DIR%\uninstall.bat as Administrator
echo.
echo Installation completed! The service is now monitoring print jobs.
echo.
pause