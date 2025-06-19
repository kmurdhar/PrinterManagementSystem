Command to run the Jobs :-

Download and run the setup:

# Create project directory
mkdir -p ~/PrintMonitorSystem && cd ~/PrintMonitorSystem

# Make the test script executable
chmod +x test_ubuntu_monitor.sh


Install prerequisites:

# Update system and install Docker
sudo apt update && sudo apt upgrade -y
sudo apt install -y docker.io docker-compose git curl python3 python3-pip cups cups-client
sudo usermod -aG docker $USER

# Install Python packages
pip3 install requests

# Log out and back in, or run:
newgrp docker

Start the system:
# Start database and backend
docker-compose up -d

# Wait a moment for services to start
sleep 10

# Run the test script
./test_ubuntu_monitor.sh


Start the print monitor:

cd print-monitor
python3 ubuntu_print_monitor.py

Access the dashboard:

# In another terminal
cd frontend
python3 -m http.server 8080

# Open browser to: http://localhost:8080
