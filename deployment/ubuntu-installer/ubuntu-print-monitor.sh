#!/bin/bash
# ubuntu-print-monitor.sh - Fixed version for externally managed Python environments
# Usage: sudo ./ubuntu-print-monitor.sh [API_IP_ADDRESS]

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
API_IP=${1:-"localhost"}
API_URL="http://${API_IP}:3000/api/print-jobs"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

echo -e "${BLUE}🖨️  Ubuntu Print Monitor Setup${NC}"
echo "=================================="
echo "API Server: $API_URL"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}❌ This script must be run as root (use sudo)${NC}"
   exit 1
fi

# Function to check command success
check_success() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Success${NC}"
    else
        echo -e "${RED}❌ Failed${NC}"
        exit 1
    fi
}

# Step 1: Update system packages
echo -e "${YELLOW}Step 1: Updating system packages${NC}"
echo "--------------------------------"
apt update && apt upgrade -y
check_success

# Step 2: Install CUPS and system dependencies
echo -e "${YELLOW}Step 2: Installing CUPS and dependencies${NC}"
echo "---------------------------------------"
apt install -y cups cups-client python3 python3-pip python3-venv curl systemd libcups2-dev
check_success

# Step 3: Create virtual environment (this avoids the externally managed environment issue)
echo -e "${YELLOW}Step 3: Creating Python virtual environment${NC}"
echo "-------------------------------------------"
VENV_DIR="/opt/print-monitor-venv"
python3 -m venv "$VENV_DIR"
check_success

# Activate virtual environment
source "$VENV_DIR/bin/activate"

# Step 4: Install Python packages in virtual environment
echo -e "${YELLOW}Step 4: Installing Python dependencies${NC}"
echo "-------------------------------------"
pip install --upgrade pip
pip install requests pycups watchdog
check_success

# Step 5: Create print monitor script
echo -e "${YELLOW}Step 5: Creating print monitor script${NC}"
echo "------------------------------------"

cat > /opt/ubuntu-print-monitor.py << 'EOF'
#!/usr/bin/env python3
"""
Ubuntu CUPS Print Monitor - Fixed Version
Monitors print jobs on Ubuntu/Linux systems using CUPS
"""

import time
import requests
import json
import subprocess
import re
import os
import signal
import sys
import logging
from datetime import datetime
from pathlib import Path

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/print-monitor.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class UbuntuPrintMonitor:
    def __init__(self, api_url="http://localhost:3000/api/print-jobs"):
        self.api_url = api_url
        self.processed_jobs = set()
        self.running = True
        
        # Setup signal handlers for graceful shutdown
        signal.signal(signal.SIGINT, self.signal_handler)
        signal.signal(signal.SIGTERM, self.signal_handler)
        
    def signal_handler(self, signum, frame):
        logger.info(f"Received signal {signum}, shutting down gracefully...")
        self.running = False
        
    def check_cups_available(self):
        """Check if CUPS is installed and running"""
        try:
            result = subprocess.run(['systemctl', 'is-active', 'cups'], 
                                  capture_output=True, text=True, timeout=5)
            if result.returncode == 0 and result.stdout.strip() == "active":
                logger.info("✅ CUPS service is running")
                return True
            else:
                logger.error("❌ CUPS service is not running")
                logger.info("   Run: sudo systemctl start cups")
                return False
        except Exception as e:
            logger.error(f"❌ Error checking CUPS: {e}")
            return False
    
    def get_print_jobs(self):
        """Get print jobs using lpstat command"""
        try:
            # Get all completed jobs from today
            result = subprocess.run(
                ['lpstat', '-W', 'completed', '-o'], 
                capture_output=True, text=True, timeout=10
            )
            
            if result.returncode != 0:
                if result.stderr:
                    logger.debug(f"lpstat stderr: {result.stderr}")
                return []
                
            jobs = []
            for line in result.stdout.strip().split('\n'):
                line = line.strip()
                if line and line not in self.processed_jobs:
                    job = self.parse_job_line(line)
                    if job:
                        jobs.append(job)
                        self.processed_jobs.add(line)
                        
            return jobs
            
        except subprocess.TimeoutExpired:
            logger.warning("⏰ CUPS command timeout")
            return []
        except Exception as e:
            logger.error(f"❌ Error getting CUPS jobs: {e}")
            return []
    
    def parse_job_line(self, line):
        """Parse CUPS job output line"""
        try:
            # Example: "printer-1 username 1024 Mon Jun 12 10:30:00 2025"
            parts = line.split()
            if len(parts) < 3:
                return None
                
            printer_job = parts[0]
            user_name = parts[1]
            
            # Extract printer name and job ID
            if '-' in printer_job:
                printer_name, job_id = printer_job.rsplit('-', 1)
                printer_name = printer_name.replace('_', ' ')
            else:
                printer_name = printer_job.replace('_', ' ')
                job_id = str(int(time.time()))
            
            # Get additional job details
            job_details = self.get_job_details(job_id, printer_name)
            
            return {
                "jobId": f"cups-{job_id}-{int(time.time())}",
                "userName": user_name,
                "machineName": os.uname().nodename,
                "printerName": printer_name,
                "documentName": job_details.get('document_name', f'Document-{job_id}'),
                "pageCount": job_details.get('page_count', 1),
                "printTime": datetime.now().isoformat(),
                "status": "completed",
                "fileSize": job_details.get('file_size', 0)
            }
            
        except Exception as e:
            logger.error(f"❌ Error parsing job line '{line}': {e}")
            return None
    
    def get_job_details(self, job_id, printer_name):
        """Get detailed information about a print job"""
        try:
            # Try to get job details from lpq
            result = subprocess.run(
                ['lpq', '-P', printer_name], 
                capture_output=True, text=True, timeout=5
            )
            
            details = {
                'document_name': f'Document-{job_id}',
                'page_count': 1,
                'file_size': 1024  # Default 1KB
            }
            
            # Parse lpq output for details
            for line in result.stdout.split('\n'):
                if job_id in line:
                    # Try to extract document name and size
                    parts = line.split()
                    if len(parts) > 3:
                        # Look for document name (usually the last part)
                        details['document_name'] = parts[-1] if parts[-1] != job_id else f'Document-{job_id}'
                        
                        # Look for size information
                        for part in parts:
                            if 'bytes' in part.lower() or part.isdigit():
                                try:
                                    size = int(re.search(r'\d+', part).group())
                                    details['file_size'] = size
                                    # Estimate pages based on file size (rough estimate)
                                    details['page_count'] = max(1, size // 50000)
                                except:
                                    pass
                        break
                        
            return details
            
        except Exception as e:
            logger.debug(f"Could not get job details for {job_id}: {e}")
            return {
                'document_name': f'Document-{job_id}',
                'page_count': 1,
                'file_size': 1024
            }
    
    def send_to_api(self, job_data):
        """Send job data to the API"""
        try:
            headers = {'Content-Type': 'application/json'}
            response = requests.post(
                self.api_url, 
                json=job_data, 
                timeout=10,
                headers=headers
            )
            
            if response.status_code == 201:
                logger.info(f"✅ Sent: {job_data['documentName']} by {job_data['userName']} on {job_data['printerName']}")
                return True
            else:
                logger.error(f"❌ API Error {response.status_code}: {response.text}")
                return False
                
        except requests.exceptions.ConnectionError:
            logger.error("❌ Cannot connect to API server")
            logger.info(f"   Check if backend is running at: {self.api_url}")
            return False
        except requests.exceptions.Timeout:
            logger.error("❌ API request timeout")
            return False
        except Exception as e:
            logger.error(f"❌ Send error: {e}")
            return False
    
    def test_api_connection(self):
        """Test if API is reachable"""
        try:
            test_url = self.api_url.replace('/print-jobs', '/stats')
            response = requests.get(test_url, timeout=5)
            if response.status_code == 200:
                logger.info("✅ API connection successful")
                return True
            else:
                logger.warning(f"⚠️ API returned status {response.status_code}")
                return False
        except Exception as e:
            logger.error(f"❌ API test failed: {e}")
            return False
    
    def get_printers(self):
        """Get list of available printers"""
        try:
            result = subprocess.run(['lpstat', '-p'], capture_output=True, text=True, timeout=5)
            printers = []
            for line in result.stdout.split('\n'):
                if line.startswith('printer'):
                    parts = line.split()
                    if len(parts) >= 2:
                        printer_name = parts[1].replace('_', ' ')
                        printers.append(printer_name)
            return printers
        except Exception as e:
            logger.error(f"❌ Error getting printer list: {e}")
            return []
    
    def monitor(self):
        """Main monitoring loop"""
        logger.info("🖨️ Ubuntu CUPS Print Monitor Started")
        logger.info(f"📡 API Endpoint: {self.api_url}")
        logger.info(f"🖥️ Monitoring system: {os.uname().nodename}")
        
        # Check if CUPS is available
        if not self.check_cups_available():
            return
        
        # Test API connection
        self.test_api_connection()
        
        # Show available printers
        printers = self.get_printers()
        if printers:
            logger.info(f"🖨️ Available printers: {', '.join(printers)}")
        else:
            logger.warning("⚠️ No printers configured")
        
        logger.info("📝 Monitoring print jobs... (Ctrl+C to stop)")
        logger.info("💡 Tip: Print something to test the monitoring!")
        
        # Main monitoring loop
        last_check = time.time()
        while self.running:
            try:
                jobs = self.get_print_jobs()
                
                for job in jobs:
                    if self.send_to_api(job):
                        # Small delay between API calls
                        time.sleep(0.5)
                
                # Clean processed jobs cache periodically (every hour)
                if time.time() - last_check > 3600:
                    if len(self.processed_jobs) > 1000:
                        self.processed_jobs.clear()
                        logger.info("🧹 Cleared job cache")
                    last_check = time.time()
                
                time.sleep(10)  # Check every 10 seconds
                
            except KeyboardInterrupt:
                logger.info("🛑 Monitor stopped by user")
                break
            except Exception as e:
                logger.error(f"❌ Monitor error: {e}")
                time.sleep(30)  # Wait longer on error
        
        logger.info("👋 Print monitor stopped")

def main():
    """Main function"""
    # Get API URL from environment or use default
    api_url = os.environ.get('PRINT_MONITOR_API', 'http://localhost:3000/api/print-jobs')
    
    # Override with command line argument if provided
    if len(sys.argv) > 1:
        api_url = sys.argv[1]
        if not api_url.startswith('http'):
            api_url = f"http://{api_url}:3000/api/print-jobs"
    
    logger.info("🖨️ Ubuntu Print Monitor")
    logger.info("=" * 50)
    
    # Create and start monitor
    monitor = UbuntuPrintMonitor(api_url)
    
    try:
        monitor.monitor()
    except KeyboardInterrupt:
        logger.info("🛑 Interrupted by user")
    except Exception as e:
        logger.error(f"❌ Fatal error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

chmod +x /opt/ubuntu-print-monitor.py
check_success

# Step 6: Create systemd service
echo -e "${YELLOW}Step 6: Creating systemd service${NC}"
echo "--------------------------------"

cat > /etc/systemd/system/print-monitor.service << EOF
[Unit]
Description=Ubuntu Print Monitor Service
After=network.target cups.service
Requires=cups.service

[Service]
Type=simple
User=root
Environment=PRINT_MONITOR_API=$API_URL
ExecStart=$VENV_DIR/bin/python /opt/ubuntu-print-monitor.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable service
systemctl daemon-reload
systemctl enable print-monitor.service
check_success

# Step 7: Start CUPS service
echo -e "${YELLOW}Step 7: Starting CUPS service${NC}"
echo "-----------------------------"
systemctl start cups
systemctl enable cups
check_success

# Step 8: Test API connection
echo -e "${YELLOW}Step 8: Testing API connection${NC}"
echo "------------------------------"
echo "Testing connection to: $API_URL"

if curl -s -m 5 "$API_URL" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ API connection successful${NC}"
    API_WORKING=true
else
    echo -e "${YELLOW}⚠️ API not reachable (this is normal if backend isn't running yet)${NC}"
    API_WORKING=false
fi

# Step 9: Start the service
echo -e "${YELLOW}Step 9: Starting print monitor service${NC}"
echo "------------------------------------"
systemctl start print-monitor.service
check_success

# Step 10: Display status and instructions
echo -e "${YELLOW}Step 10: Installation complete!${NC}"
echo "-------------------------------"
echo ""
echo -e "${GREEN}🎉 Ubuntu Print Monitor Setup Complete!${NC}"
echo ""
echo "📋 Service Information:"
echo "   Status: $(systemctl is-active print-monitor.service)"
echo "   Logs:   journalctl -u print-monitor.service -f"
echo "   Config: /etc/systemd/system/print-monitor.service"
echo ""
echo "🖨️ CUPS Information:"
echo "   Status: $(systemctl is-active cups.service)"
echo "   Config: http://localhost:631 (CUPS web interface)"
echo ""
echo "🔧 Useful Commands:"
echo "   sudo systemctl status print-monitor.service    # Check service status"
echo "   sudo systemctl restart print-monitor.service   # Restart service"
echo "   sudo journalctl -u print-monitor.service -f    # View live logs"
echo "   lpstat -p                                       # List printers"
echo "   lpstat -W completed -o                          # List completed jobs"
echo ""

if [ "$API_WORKING" = true ]; then
    echo -e "${GREEN}✅ Ready to monitor print jobs!${NC}"
    echo "   Try printing a test page to verify monitoring."
else
    echo -e "${YELLOW}⚠️ Start your backend server, then restart the service:${NC}"
    echo "   sudo systemctl restart print-monitor.service"
fi

echo ""
echo "📊 Dashboard: http://${API_IP}:8080"
echo ""

# Display current status
echo -e "${BLUE}Current Status:${NC}"
echo "   Print Monitor: $(systemctl is-active print-monitor.service)"
echo "   CUPS Service:  $(systemctl is-active cups.service)"
echo "   Available Printers:"
if command -v lpstat &> /dev/null; then
    lpstat -p 2>/dev/null | grep "printer" | head -5 || echo "     No printers configured"
else
    echo "     CUPS commands not available"
fi

echo ""
echo -e "${GREEN}Setup completed successfully! 🎉${NC}"