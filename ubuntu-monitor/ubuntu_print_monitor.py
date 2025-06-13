#!/usr/bin/env python3
"""
Ubuntu CUPS Print Monitor
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
from datetime import datetime
from pathlib import Path

class UbuntuPrintMonitor:
    def __init__(self, api_url="http://localhost:3000/api/print-jobs"):
        self.api_url = api_url
        self.last_job_id = 0
        self.processed_jobs = set()
        self.running = True
        
        # Setup signal handlers for graceful shutdown
        signal.signal(signal.SIGINT, self.signal_handler)
        signal.signal(signal.SIGTERM, self.signal_handler)
        
    def signal_handler(self, signum, frame):
        print(f"\n🛑 Received signal {signum}, shutting down gracefully...")
        self.running = False
        
    def check_cups_available(self):
        """Check if CUPS is installed and running"""
        try:
            result = subprocess.run(['lpstat', '-r'], capture_output=True, text=True, timeout=5)
            if result.returncode == 0 and "scheduler is running" in result.stdout:
                print("✅ CUPS is running and available")
                return True
            else:
                print("❌ CUPS scheduler is not running")
                print("   Run: sudo systemctl start cups")
                return False
        except FileNotFoundError:
            print("❌ CUPS is not installed")
            print("   Run: sudo apt install cups cups-client")
            return False
        except Exception as e:
            print(f"❌ Error checking CUPS: {e}")
            return False
    
    def get_completed_jobs(self):
        """Get completed print jobs from CUPS"""
        try:
            # Get completed jobs with verbose output
            result = subprocess.run(
                ['lpstat', '-W', 'completed', '-o'], 
                capture_output=True, text=True, timeout=10
            )
            
            if result.returncode != 0:
                return []
                
            jobs = []
            for line in result.stdout.strip().split('\n'):
                if line.strip():
                    job = self.parse_job_line(line)
                    if job:
                        job_key = f"{job['jobId']}-{job['printerName']}-{job['documentName']}"
                        if job_key not in self.processed_jobs:
                            jobs.append(job)
                            self.processed_jobs.add(job_key)
                            
            return jobs
            
        except subprocess.TimeoutExpired:
            print("⏰ CUPS command timeout")
            return []
        except Exception as e:
            print(f"❌ Error getting CUPS jobs: {e}")
            return []
    
    def parse_job_line(self, line):
        """Parse CUPS job output line"""
        try:
            # Example line: "HP_LaserJet-1 username 1024 Mon 11 Jun 2025 10:30:00 AM"
            parts = line.split()
            if len(parts) < 3:
                return None
                
            printer_job = parts[0]  # e.g., "HP_LaserJet-1"
            user_name = parts[1]
            
            # Extract job ID and printer name
            if '-' in printer_job:
                printer_name, job_id = printer_job.rsplit('-', 1)
                printer_name = printer_name.replace('_', ' ')
            else:
                printer_name = printer_job.replace('_', ' ')
                job_id = str(int(time.time()))
            
            # Get additional job details
            job_details = self.get_job_details(job_id)
            
            return {
                "jobId": f"cups-{job_id}-{int(time.time())}",
                "userName": user_name,
                "machineName": os.uname().nodename,
                "printerName": printer_name,
                "documentName": job_details.get('document_name', 'Unknown Document'),
                "pageCount": job_details.get('page_count', 1),
                "printTime": datetime.now().isoformat(),
                "status": "completed",
                "fileSize": job_details.get('file_size', 0)
            }
            
        except Exception as e:
            print(f"❌ Error parsing job line '{line}': {e}")
            return None
    
    def get_job_details(self, job_id):
        """Get detailed information about a print job"""
        try:
            result = subprocess.run(
                ['lpstat', '-l', '-j', str(job_id)], 
                capture_output=True, text=True, timeout=5
            )
            
            details = {
                'document_name': 'Unknown Document',
                'page_count': 1,
                'file_size': 0
            }
            
            for line in result.stdout.split('\n'):
                line_lower = line.strip().lower()
                if 'document-name' in line_lower or 'document name' in line_lower:
                    # Extract document name
                    if '=' in line:
                        name = line.split('=')[-1].strip()
                        if name:
                            details['document_name'] = name
                elif 'pages' in line_lower or 'page-count' in line_lower:
                    # Extract page count
                    numbers = re.findall(r'\d+', line)
                    if numbers:
                        details['page_count'] = int(numbers[0])
                elif 'size' in line_lower:
                    # Extract file size
                    numbers = re.findall(r'\d+', line)
                    if numbers:
                        details['file_size'] = int(numbers[0])
                        
            return details
            
        except Exception as e:
            print(f"⚠️ Could not get job details for {job_id}: {e}")
            return {'document_name': 'Unknown Document', 'page_count': 1, 'file_size': 0}
    
    def get_printer_list(self):
        """Get list of available printers"""
        try:
            result = subprocess.run(['lpstat', '-p'], capture_output=True, text=True, timeout=5)
            printers = []
            for line in result.stdout.split('\n'):
                if line.startswith('printer'):
                    parts = line.split()
                    if len(parts) >= 2:
                        printer_name = parts[1]
                        printers.append(printer_name.replace('_', ' '))
            return printers
        except Exception as e:
            print(f"❌ Error getting printer list: {e}")
            return []
    
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
                print(f"✅ Sent: {job_data['documentName']} by {job_data['userName']} on {job_data['printerName']}")
                return True
            else:
                print(f"❌ API Error {response.status_code}: {response.text}")
                return False
                
        except requests.exceptions.ConnectionError:
            print("❌ Cannot connect to API server (http://localhost:3000)")
            print("   Make sure the backend is running: docker-compose ps")
            return False
        except requests.exceptions.Timeout:
            print("❌ API request timeout")
            return False
        except Exception as e:
            print(f"❌ Send error: {e}")
            return False
    
    def test_api_connection(self):
        """Test if API is reachable"""
        try:
            test_url = self.api_url.replace('/print-jobs', '/stats')
            response = requests.get(test_url, timeout=5)
            if response.status_code == 200:
                print("✅ API connection successful")
                return True
            else:
                print(f"⚠️ API returned status {response.status_code}")
                return False
        except Exception as e:
            print(f"❌ API test failed: {e}")
            return False
    
    def test_print_job(self):
        """Create a test print job to verify monitoring"""
        try:
            test_content = f"""
Test Print Job - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

This is a test print job created by the Ubuntu Print Monitor.
If you see this job appear in the dashboard, monitoring is working correctly!

System: {os.uname().nodename}
User: {os.getlogin()}
Time: {datetime.now().isoformat()}
"""
            
            # Create a temporary file
            temp_file = '/tmp/print_monitor_test.txt'
            with open(temp_file, 'w') as f:
                f.write(test_content)
            
            # Send to default printer
            result = subprocess.run(['lp', temp_file], capture_output=True, text=True)
            
            if result.returncode == 0:
                print(f"✅ Test print job sent: {result.stdout.strip()}")
                # Clean up
                os.remove(temp_file)
                return True
            else:
                print(f"❌ Failed to send test print: {result.stderr}")
                return False
                
        except Exception as e:
            print(f"❌ Error creating test print job: {e}")
            return False
    
    def monitor(self):
        """Main monitoring loop"""
        print("🖨️ Ubuntu CUPS Print Monitor Started")
        print(f"📡 API Endpoint: {self.api_url}")
        print(f"🖥️ Monitoring system: {os.uname().nodename}")
        
        # Check if CUPS is available
        if not self.check_cups_available():
            return
        
        # Test API connection
        if not self.test_api_connection():
            print("⚠️ API not reachable, but continuing to monitor...")
        
        # Show available printers
        printers = self.get_printer_list()
        if printers:
            print(f"🖨️ Available printers: {', '.join(printers)}")
        else:
            print("⚠️ No printers found. Add a printer first:")
            print("   System Settings > Printers")
        
        print("\n📝 Monitoring print jobs... (Ctrl+C to stop)")
        print("💡 Tip: Print something to test the monitoring!")
        
        # Main monitoring loop
        while self.running:
            try:
                jobs = self.get_completed_jobs()
                
                for job in jobs:
                    self.send_to_api(job)
                
                # Clean processed jobs cache periodically
                if len(self.processed_jobs) > 1000:
                    self.processed_jobs.clear()
                    print("🧹 Cleared job cache")
                
                time.sleep(5)  # Check every 5 seconds
                
            except KeyboardInterrupt:
                print("\n🛑 Monitor stopped by user")
                break
            except Exception as e:
                print(f"❌ Monitor error: {e}")
                time.sleep(10)  # Wait longer on error
        
        print("👋 Print monitor stopped")

def main():
    """Main function"""
    print("🖨️ Ubuntu Print Monitor")
    print("=" * 50)
    
    # Check command line arguments
    api_url = "http://localhost:3000/api/print-jobs"
    if len(sys.argv) > 1:
        api_url = sys.argv[1]
    
    # Create and start monitor
    monitor = UbuntuPrintMonitor(api_url)
    
    try:
        monitor.monitor()
    except KeyboardInterrupt:
        print("\n🛑 Interrupted by user")
    except Exception as e:
        print(f"❌ Fatal error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
