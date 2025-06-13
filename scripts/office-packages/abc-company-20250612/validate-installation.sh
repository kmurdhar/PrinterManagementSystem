#!/bin/bash
# Validate installation for ABC Company

API_SERVER="192.168.1.100"
EXPECTED_COMPUTERS=10

echo "Validating Print Monitor Installation for ABC Company"
echo "====================================================="
echo ""

# Test API connection
echo "1. Testing API connection..."
if curl -s "http://$API_SERVER:3000/api/health" > /dev/null; then
    echo "✅ API is responding"
else
    echo "❌ API connection failed"
    exit 1
fi

# Get current statistics
echo ""
echo "2. Getting current statistics..."
stats=$(curl -s "http://$API_SERVER:3000/api/stats")

if [ -n "$stats" ]; then
    total_jobs=$(echo "$stats" | grep -o '"totalJobs":[0-9]*' | cut -d':' -f2)
    total_pages=$(echo "$stats" | grep -o '"totalPages":[0-9]*' | cut -d':' -f2)
    
    echo "📊 Total Jobs: $total_jobs"
    echo "📄 Total Pages: $total_pages"
else
    echo "❌ Could not retrieve statistics"
fi

# Check computer coverage
echo ""
echo "3. Checking computer coverage..."
recent_jobs=$(curl -s "http://$API_SERVER:3000/api/print-jobs?limit=100")

if [ -n "$recent_jobs" ]; then
    unique_computers=$(echo "$recent_jobs" | grep -o '"machine_name":"[^"]*"' | sort -u | wc -l)
    echo "🖥️  Computers reporting: $unique_computers / $EXPECTED_COMPUTERS"
    
    if [ "$unique_computers" -eq "$EXPECTED_COMPUTERS" ]; then
        echo "✅ All computers are reporting"
    else
        echo "⚠️  Missing computers - check installations"
    fi
else
    echo "❌ Could not retrieve job data"
fi

echo ""
echo "4. Dashboard access: http://$API_SERVER"
echo ""

if [ "$unique_computers" -eq "$EXPECTED_COMPUTERS" ] && [ "$total_jobs" -gt 0 ]; then
    echo "🎉 Installation validation PASSED for ABC Company!"
    echo "   All systems are working correctly."
else
    echo "⚠️  Installation validation needs attention."
    echo "   Check individual computer installations."
fi
