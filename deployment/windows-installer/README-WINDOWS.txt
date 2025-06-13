Windows Print Monitor Installation Guide
========================================

Requirements:
- Windows 10/11 or Windows Server 2016+
- Administrator privileges
- Network access to the print monitoring server

Installation Steps:
1. Right-click on "install-print-monitor.bat"
2. Select "Run as administrator"
3. Follow the installation prompts
4. Service will start automatically

Files Included:
- PrintListener.exe             Main service executable
- appsettings.json             Configuration file
- install-print-monitor.bat    Installation script
- README-WINDOWS.txt           This file

Configuration:
Edit appsettings.json to change:
- API server address (BaseUrl)
- Office name (OfficeName)
- Request timeout (Timeout)

Verification:
1. Open Services.msc
2. Look for "Print Monitor Service"
3. Status should be "Running"

Testing:
1. Print any document
2. Check the dashboard
3. Your print job should appear within seconds

Troubleshooting:
- If service won't start, check Windows Event Viewer
- Ensure Windows Firewall allows outbound connections
- Verify network connectivity to API server

Service Management:
- Start: sc start "Print Monitor Service"
- Stop: sc stop "Print Monitor Service"
- Status: sc query "Print Monitor Service"

Uninstall:
- Run C:\PrintMonitor\uninstall.bat as Administrator

Log Files:
- Service logs: C:\PrintMonitor\logs\
- Windows Event Log: Event Viewer > Application

Support:
Check the main dashboard for help and documentation.

© 2025 Print Monitor Systems