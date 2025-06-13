Ubuntu Print Monitor Installation Guide
=======================================

Requirements:
- Ubuntu 18.04+ or other Debian-based Linux
- sudo privileges
- CUPS printing system
- Network access to the print monitoring server

Installation Steps:
1. Copy files to the Ubuntu computer
2. Make installer executable: chmod +x install-ubuntu-print-monitor.sh
3. Run installer: sudo ./install-ubuntu-print-monitor.sh [API_SERVER_IP]
4. Service will start automatically

Files Included:
- ubuntu_print_monitor.py              Main service script
- install-ubuntu-print-monitor.sh      Installation script
- README-UBUNTU.txt                    This file

Example Installation:
sudo ./install-ubuntu-print-monitor.sh 192.168.1.100

Configuration:
The installer creates /etc/printmonitor/config.ini with:
- API server URL
- Office name
- Monitoring settings
- Logging configuration

Verification:
sudo systemctl status printmonitor

Testing:
1. Print any document: echo "test" | lp
2. Check the dashboard
3. Your print job should appear within seconds

Management Commands:
- printmonitor-status     # Check service status
- printmonitor-logs       # View live logs  
- printmonitor-test       # Send test print job
- printmonitor-uninstall  # Remove service

Systemctl Commands:
- sudo systemctl status print-monitor.service     # Check status
- sudo systemctl restart print-monitor.service     # Restart service
- sudo systemctl stop print-monitor.service        # Stop service
- sudo systemctl start print-monitor.service       # Start service

Log Files:
- Service logs: /var/log/printmonitor/printmonitor.log
- System logs: sudo journalctl -u printmonitor

Troubleshooting:
- Check logs: sudo journalctl -u printmonitor -f
- Restart service: sudo systemctl restart printmonitor
- Test CUPS: lpstat -p
- Test API: curl http://API_SERVER:3000/api/health

Configuration File:
/etc/printmonitor/config.ini

Service User:
The service runs as user 'printmonitor' for security

Uninstall:
sudo printmonitor-uninstall

Dependencies:
- python3
- python3-pip
- requests (installed automatically)
- cups
- cups-client

Support:
Check the main dashboard for help and documentation.

© 2025 Print Monitor Systems