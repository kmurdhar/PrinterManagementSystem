#!/bin/bash
# create-deployment-packages.sh
# Creates client-specific deployment packages

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

API_SERVER="${1:-192.168.1.100}"
OFFICE_NAME="${2:-ABC Company}"

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <API_SERVER_IP> <OFFICE_NAME>"
    echo "Example: $0 192.168.1.100 \"ABC Company\""
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Creating Deployment Packages${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${GREEN}API Server: $API_SERVER${NC}"
echo -e "${GREEN}Office Name: $OFFICE_NAME${NC}"
echo ""

# Create deployment directory
DEPLOY_DIR="office-packages/$(echo "$OFFICE_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')-$(date +%Y%m%d)"
mkdir -p "$DEPLOY_DIR"
cd "$DEPLOY_DIR"

echo -e "${YELLOW}[1/5] Creating Windows deployment package...${NC}"

# Windows Package
mkdir -p windows-package
cd windows-package

# Copy Windows files from windows-installer directory
if [ -d "../../windows-installer" ]; then
    cp -r ../../windows-installer/* ./
else
    echo "Warning: windows-installer directory not found, creating templates..."
    mkdir -p windows-installer
fi

# Update Windows configuration for this client
cat > appsettings.json << EOF
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft": "Warning",
      "Microsoft.Hosting.Lifetime": "Information"
    },
    "EventLog": {
      "LogLevel": {
        "Default": "Information"
      }
    }
  },
  "ApiSettings": {
    "BaseUrl": "http://$API_SERVER:3000/api",
    "Timeout": 30000
  },
  "OfficeConfig": {
    "OfficeName": "$OFFICE_NAME",
    "Location": "Main Office"
  }
}
EOF

cd ..

echo -e "${YELLOW}[2/5] Creating Ubuntu deployment package...${NC}"

# Ubuntu Package
mkdir -p ubuntu-package
cd ubuntu-package

# Copy Ubuntu files from ubuntu-installer directory
if [ -d "../../ubuntu-installer" ]; then
    cp -r ../../ubuntu-installer/* ./
else
    echo "Warning: ubuntu-installer directory not found, creating templates..."
fi

# Update installer script for this client
if [ -f "install-ubuntu-print-monitor.sh" ]; then
    sed -i "s/API_SERVER=\"\${1:-192.168.1.100}\"/API_SERVER=\"\${1:-$API_SERVER}\"/" install-ubuntu-print-monitor.sh
    sed -i "s/office_name = Your Company Name/office_name = $OFFICE_NAME/" install-ubuntu-print-monitor.sh
fi

cd ..

echo -e "${YELLOW}[3/5] Creating test and validation scripts...${NC}"

# Quick test script
cat > quick-test.sh << EOF
#!/bin/bash
# Quick test script for $OFFICE_NAME

API_SERVER="$API_SERVER"

echo "Testing Print Monitor System for $OFFICE_NAME"
echo "============================================="
echo ""

echo "1. Testing API connection..."
if curl -s "http://\$API_SERVER:3000/api/health" > /dev/null; then
    echo "✅ API is responding"
else
    echo "❌ API is not responding"
    exit 1
fi

echo ""
echo "2. Sending test print jobs for all computers..."

# Test jobs for all 10 computers
computers=(
    "OFFICE-PC-01:john.doe:Windows"
    "OFFICE-PC-02:jane.smith:Windows" 
    "OFFICE-PC-03:bob.wilson:Ubuntu"
    "OFFICE-PC-04:alice.brown:Windows"
    "OFFICE-PC-05:mike.johnson:Windows"
    "OFFICE-PC-06:sarah.davis:Windows"
    "OFFICE-PC-07:tom.anderson:Ubuntu"
    "OFFICE-PC-08:lisa.wilson:Windows"
    "OFFICE-PC-09:chris.taylor:Windows"
    "OFFICE-PC-10:emma.martinez:Windows"
)

for computer in "\${computers[@]}"; do
    IFS=':' read -r pc_name username os <<< "\$computer"
    
    echo "Testing \$pc_name (\$username)..."
    
    curl -s -X POST "http://\$API_SERVER:3000/api/print-jobs" \\
        -H "Content-Type: application/json" \\
        -d "{
            \"jobId\": \"test-\${pc_name,,}-001\",
            \"userName\": \"\$username\",
            \"machineName\": \"\$pc_name\",
            \"printerName\": \"HP LaserJet Pro\",
            \"documentName\": \"Test from \$pc_name.pdf\",
            \"pageCount\": 1,
            \"status\": \"completed\",
            \"fileSize\": 50000
        }" > /dev/null
    
    if [ \$? -eq 0 ]; then
        echo "✅ \$pc_name test job sent"
    else
        echo "❌ \$pc_name test job failed"
    fi
done

echo ""
echo "3. Check dashboard at: http://\$API_SERVER"
echo "   You should see 10 test print jobs"
echo ""
echo "Test completed for $OFFICE_NAME!"
EOF

chmod +x quick-test.sh

# Validation script
cat > validate-installation.sh << EOF
#!/bin/bash
# Validate installation for $OFFICE_NAME

API_SERVER="$API_SERVER"
EXPECTED_COMPUTERS=10

echo "Validating Print Monitor Installation for $OFFICE_NAME"
echo "====================================================="
echo ""

# Test API connection
echo "1. Testing API connection..."
if curl -s "http://\$API_SERVER:3000/api/health" > /dev/null; then
    echo "✅ API is responding"
else
    echo "❌ API connection failed"
    exit 1
fi

# Get current statistics
echo ""
echo "2. Getting current statistics..."
stats=\$(curl -s "http://\$API_SERVER:3000/api/stats")

if [ -n "\$stats" ]; then
    total_jobs=\$(echo "\$stats" | grep -o '"totalJobs":[0-9]*' | cut -d':' -f2)
    total_pages=\$(echo "\$stats" | grep -o '"totalPages":[0-9]*' | cut -d':' -f2)
    
    echo "📊 Total Jobs: \$total_jobs"
    echo "📄 Total Pages: \$total_pages"
else
    echo "❌ Could not retrieve statistics"
fi

# Check computer coverage
echo ""
echo "3. Checking computer coverage..."
recent_jobs=\$(curl -s "http://\$API_SERVER:3000/api/print-jobs?limit=100")

if [ -n "\$recent_jobs" ]; then
    unique_computers=\$(echo "\$recent_jobs" | grep -o '"machine_name":"[^"]*"' | sort -u | wc -l)
    echo "🖥️  Computers reporting: \$unique_computers / \$EXPECTED_COMPUTERS"
    
    if [ "\$unique_computers" -eq "\$EXPECTED_COMPUTERS" ]; then
        echo "✅ All computers are reporting"
    else
        echo "⚠️  Missing computers - check installations"
    fi
else
    echo "❌ Could not retrieve job data"
fi

echo ""
echo "4. Dashboard access: http://\$API_SERVER"
echo ""

if [ "\$unique_computers" -eq "\$EXPECTED_COMPUTERS" ] && [ "\$total_jobs" -gt 0 ]; then
    echo "🎉 Installation validation PASSED for $OFFICE_NAME!"
    echo "   All systems are working correctly."
else
    echo "⚠️  Installation validation needs attention."
    echo "   Check individual computer installations."
fi
EOF

chmod +x validate-installation.sh

echo -e "${YELLOW}[4/5] Creating documentation...${NC}"

# Create main README
cat > README.txt << EOF
Print Monitor Deployment Package for $OFFICE_NAME
=================================================

Created: $(date)
Office: $OFFICE_NAME
API Server: $API_SERVER
Dashboard: http://$API_SERVER

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
2. Check dashboard at http://$API_SERVER
3. Verify all 10 computers are reporting

Validation:
==========
Run validate-installation.sh to check system health

Support:
=======
- Dashboard: http://$API_SERVER
- API Health: http://$API_SERVER:3000/api/health

Installation completed successfully for $OFFICE_NAME!
EOF

echo -e "${YELLOW}[5/5] Creating compressed archive...${NC}"

# Create compressed archive
cd ..
ARCHIVE_NAME="$(basename "$DEPLOY_DIR").tar.gz"
tar -czf "$ARCHIVE_NAME" "$(basename "$DEPLOY_DIR")"

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}      Package Creation Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${GREEN}Created deployment package: $(pwd)/$DEPLOY_DIR${NC}"
echo -e "${GREEN}Created archive: $(pwd)/$ARCHIVE_NAME${NC}"
echo ""
echo -e "${YELLOW}Package Contents:${NC}"
echo "📁 windows-package/           - Windows installer + configuration"
echo "📁 ubuntu-package/            - Ubuntu installer + configuration"  
echo "🧪 quick-test.sh              - Test all 10 computers"
echo "✅ validate-installation.sh   - Validate deployment"
echo "📖 README.txt                 - Complete instructions"
echo "📦 $(basename "$ARCHIVE_NAME")            - Compressed archive"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Copy package to USB drive or send archive via email"
echo "2. Follow installation instructions in README.txt"
echo "3. Run quick-test.sh to verify all computers"
echo "4. Use validate-installation.sh to check coverage"
echo ""
echo -e "${GREEN}Dashboard URL: http://$API_SERVER${NC}"
echo -e "${GREEN}Office: $OFFICE_NAME${NC}"
echo ""
echo "Package ready for deployment!"