#!/usr/bin/env python3
"""
Ubuntu CUPS Print Monitor Service
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
import configparser
import argparse
from datetime import datetime
from pathlib import Path
import socket

class UbuntuPrintMonitorService:
    def __init__(self, config_file="/etc/printmonitor/config.ini"):
        self.config_file = config_file
        self.config = configparser.ConfigParser()
        self.load_config()
        
        # Setup logging
        self.setup_logging()
        
        # Runtime variables
        self.processed_jobs = set()
        self.running = True
        self.api_url = self.config.get('server', 'api_url')
        self.office_name = self.config.get('server', 'office_name', fallback='Unknown Office')
        self.machine_name = socket.gethostname()
        self.monitor_interval = self.config.getint('cups', 'monitor_interval', fallback=5)
        
        # Setup signal handlers for graceful shutdown
        signal.signal(signal.SIGINT, self.signal_handler)
        signal.signal(signal.SIGTERM, self.signal_handler)
        
        self.logger.info(f"Print Monitor Service initialized for {self.office_name}")
        
    def load_config(self):
        """Load configuration from file"""
        if os.path.exists(self.config_file):
            self.config.read(self.config_file)
        else:
            # Create default config
            self.create_default_config()
            
    def create_default_config(self):
        """Create default configuration file"""
        self.config['server'] = {
            'api_url': 'http://192.168.1.100:3000/api/print-jobs',
            'office_name': 'Your Company Name',
            'timeout': '30'
        }
        self.config['cups'] = {
            'monitor_interval': '5',
            'log_level': 'INFO'
        }
        self.config['logging'] = {
            'log_file': '/var/log/printmonitor/printmonitor.log',
            'log_level': 'INFO',
            'max_size_mb': '10',
            'backup_count': '5'
        }
        
        # Create config directory
        os.makedirs(os.path.dirname(self.config_file), exist_ok=True)
        
        # Write config file
        with open(self.config_file, 'w') as f:
            self.config.write(f)
            
        print(f"Created default configuration at {self.config_file}")
        
    def setup_logging(self):
        """Setup logging configuration"""
        log_file = self.config.get('logging', 'log_file', fallback='/var/log/printmonitor/printmonitor.log')
        log_level = self.config.get('logging', 'log_level', fallback='INFO')
        
        # Create log directory
        os.makedirs(os.path.dirname(log_file), exist_ok=True)
        
        # Configure logging
        logging.basicConfig(
            level=getattr(logging, log_level.upper()),
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(log_file),
                logging.StreamHandler(sys.stdout)
            ]
        )
        
        self.logger = logging.getLogger('PrintMonitor')
        
    def signal_handler(self, signum, frame):
        """Handle shutdown signals"""
        self.logger.info(f"Received signal {signum}, shutting down gracefully...")
        self.running = False
        
    def check_cups_available(self):
        """Check if CUPS is installed and running"""
        try:
            result = subprocess.run(['lpstat', '-r'], capture_output=True, text=True, timeout=5)
            if result.returncode == 0 and "scheduler is running" in result.stdout:
                self.logger.info("CUPS is running and available")
                return True
            else:
                self.logger.error("CUPS scheduler is not running")
                return False
        except FileNotFoundError:
            self.logger.error("CUPS is not installed")
            return False
        except Exception as e:
            self.logger.error(f"Error checking CUPS: {e}")
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
            self.logger.warning("CUPS command timeout")
            return []
        except Exception as e:
            self.logger.error(f"Error getting CUPS jobs: {e}")
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
                "machineName": self.machine_name,
                "printerName": printer_name,
                "documentName": job_details.get('document_name', 'Unknown Document'),
                "pageCount": job_details.get('page_count', 1),
                "printTime": datetime.now().isoformat(),
                "status": "completed",
                "fileSize": job_details.get('file_size', 0)
            }
            
        except Exception as e:
            self.logger.error(f"Error parsing job line '{line}': {e}")
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
            self.logger.warning(f"Could not get job details for {job_id}: {e}")
            return {'document_name': 'Unknown Document', 'page_count': 1, 'file_size': 0}
    
    def send_to_api(self, job_data):
        """Send job data to the API"""
        try:
            timeout = self.config.getint('server', 'timeout', fallback=30)
            
            headers = {'Content-Type': 'application/json'}
            response = requests.post(
                self.api_url, 
                json=job_data, 
                timeout=timeout,
                headers=headers
            )
            
            if response.status_code == 201:
                self.logger.info(f"Sent: {job_data['documentName']} by {job_data['userName']} on {job_data['printerName']}")
                return True
            else:
                self.logger.error(f"API Error {response.status_code}: {response.text}")
                return False
                
        except requests.exceptions.ConnectionError:
            self.logger.error("Cannot connect to API server")
            return False
        except requests.exceptions.Timeout:
            self.logger.error("API request timeout")
            return False
        except Exception as e:
            self.logger.error(f"Send error: {e}")
            return False
    
    def test_api_connection(self):
        """Test if API is reachable"""
        try:
            test_url = self.api_url.replace('/print-jobs', '/health')
            response = requests.get(test_url, timeout=5)
            if response.status_code == 200:
                self.logger.info("API connection successful")
                return True
            else:
                self.logger.warning(f"API returned status {response.status_code}")
                return False
        except Exception as e:
            self.logger.error(f"API test failed: {e}")
            return False
    
    def run(self):
        """Main service loop"""
        self.logger.info(f"Ubuntu CUPS Print Monitor Service Starting")
        self.logger.info(f"API Endpoint: {self.api_url}")
        self.logger.info(f"Monitoring system: {self.machine_name}")
        self.logger.info(f"Office: {self.office_name}")
        
        # Check if CUPS is available
        if not self.check_cups_available():
            self.logger.error("CUPS not available, exiting")
            return
        
        # Test API connection
        if not self.test_api_connection():
            self.logger.warning("API not reachable, but continuing to monitor...")
        
        self.logger.info("Monitoring print jobs... (SIGTERM or SIGINT to stop)")
        
        # Main monitoring loop
        while self.running:
            try:
                jobs = self.get_completed_jobs()
                
                for job in jobs:
                    self.send_to_api(job)
                
                # Clean processed jobs cache periodically
                if len(self.processed_jobs) > 1000:
                    self.processed_jobs.clear()
                    self.logger.info("Cleared job cache")
                
                time.sleep(self.monitor_interval)
                
            except KeyboardInterrupt:
                self.logger.info("Monitor stopped by user")
                break
            except Exception as e:
                self.logger.error(f"Monitor error: {e}")
                time.sleep(10)  # Wait longer on error
        
        self.logger.info("Print monitor service stopped")

def main():
    """Main function"""
    parser = argparse.ArgumentParser(description='Ubuntu Print Monitor Service')
    parser.add_argument('--config', default='/etc/printmonitor/config.ini', help='Config file path')
    parser.add_argument('--daemon', action='store_true', help='Run as daemon')
    parser.add_argument('--test', action='store_true', help='Test configuration and exit')
    
    args = parser.parse_args()
    
    # Create service instance
    service = UbuntuPrintMonitorService(args.config)
    
    if args.test:
        print("Testing configuration...")
        print(f"Config file: {args.config}")
        print(f"API URL: {service.api_url}")
        print(f"Office: {service.office_name}")
        print(f"Machine: {service.machine_name}")
        
        if service.check_cups_available():
            print("✅ CUPS is available")
        else:
            print("❌ CUPS is not available")
            
        if service.test_api_connection():
            print("✅ API connection successful")
        else:
            print("❌ API connection failed")
            
        return
    
    try:
        service.run()
    except KeyboardInterrupt:
        print("\nInterrupted by user")
    except Exception as e:
        print(f"Fatal error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()