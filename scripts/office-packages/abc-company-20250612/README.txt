Print Monitor Deployment Package for ABC Company
=================================================

Created: Thu Jun 12 01:23:22 PM IST 2025
Office: ABC Company
API Server: 192.168.1.100
Dashboard: http://192.168.1.100

Contents:
========
1. windows-package/     - Windows Print Listener installation
2. ubuntu-package/      - Ubuntu Print Monitor installation  
3. quick-test.sh        - Test script for all computers
4. validate-installation.sh - Installation validation
5. README.txt           - This file

Quick Start:
===========

Windows Computers (8 machines):
1. Copy windows-package/ to each Windows computer
2. Right-click install-print-monitor.bat → "Run as administrator"
3. Follow installation prompts

Ubuntu Computers (2 machines):
1. Copy ubuntu-package/ to each Ubuntu computer
2. Run: sudo ./install-ubuntu-print-monitor.sh
3. Verify with: sudo systemctl status printmonitor

Computer List:
=============
OFFICE-PC-01 (Windows) - john.doe - IT
OFFICE-PC-02 (Windows) - jane.smith - Marketing  
OFFICE-PC-03 (Ubuntu)  - bob.wilson - Finance
OFFICE-PC-04 (Windows) - alice.brown - HR
OFFICE-PC-05 (Windows) - mike.johnson - Sales
OFFICE-PC-06 (Windows) - sarah.davis - Marketing
OFFICE-PC-07 (Ubuntu)  - tom.anderson - IT
OFFICE-PC-08 (Windows) - lisa.wilson - Finance
OFFICE-PC-09 (Windows) - chris.taylor - Sales
OFFICE-PC-10 (Windows) - emma.martinez - HR

Testing:
=======
1. Run quick-test.sh to send test jobs from all computers
2. Check dashboard at http://192.168.1.100
3. Verify all 10 computers are reporting

Validation:
==========
Run validate-installation.sh to check system health

Support:
=======
- Dashboard: http://192.168.1.100
- API Health: http://192.168.1.100:3000/api/health

Installation completed successfully for ABC Company!
