#!/bin/bash
# Quick test script for ABC Company

API_SERVER="192.168.1.100"

echo "Testing Print Monitor System for ABC Company"
echo "============================================="
echo ""

echo "1. Testing API connection..."
if curl -s "http://$API_SERVER:3000/api/health" > /dev/null; then
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

for computer in "${computers[@]}"; do
    IFS=':' read -r pc_name username os <<< "$computer"
    
    echo "Testing $pc_name ($username)..."
    
    curl -s -X POST "http://$API_SERVER:3000/api/print-jobs" \
        -H "Content-Type: application/json" \
        -d "{
            \"jobId\": \"test-${pc_name,,}-001\",
            \"userName\": \"$username\",
            \"machineName\": \"$pc_name\",
            \"printerName\": \"HP LaserJet Pro\",
            \"documentName\": \"Test from $pc_name.pdf\",
            \"pageCount\": 1,
            \"status\": \"completed\",
            \"fileSize\": 50000
        }" > /dev/null
    
    if [ $? -eq 0 ]; then
        echo "✅ $pc_name test job sent"
    else
        echo "❌ $pc_name test job failed"
    fi
done

echo ""
echo "3. Check dashboard at: http://$API_SERVER"
echo "   You should see 10 test print jobs"
echo ""
echo "Test completed for ABC Company!"
