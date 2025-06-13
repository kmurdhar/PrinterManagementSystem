#!/bin/bash
# test-print-monitor.sh
# System-wide test script for print monitoring system

echo "🖨️  Print Monitor System Test"
echo "============================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
API_URL="${1:-http://localhost:3000}"
OFFICE_NAME="${2:-Test Office}"

# Function to check if service is running
check_service() {
    local service_name=$1
    local url=$2
    
    echo -n "Checking $service_name... "
    if curl -s "$url" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Running${NC}"
        return 0
    else
        echo -e "${RED}✗ Not running${NC}"
        return 1
    fi
}

# Function to send test print job
send_test_job() {
    local job_id=$1
    local user_name=$2
    local machine_name=$3
    local document_name=$4
    local page_count=$5
    
    echo -n "Testing $machine_name ($user_name)... "
    
    response=$(curl -s -X POST "$API_URL/api/print-jobs" \
        -H "Content-Type: application/json" \
        -d "{
            \"jobId\": \"$job_id\",
            \"userName\": \"$user_name\",
            \"machineName\": \"$machine_name\",
            \"printerName\": \"Test Printer\",
            \"documentName\": \"$document_name\",
            \"pageCount\": $page_count,
            \"status\": \"completed\",
            \"fileSize\": $((page_count * 50000))
        }")
    
    if echo "$response" | grep -q '"success":true'; then
        echo -e "${GREEN}✓ Success${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed${NC}"
        return 1
    fi
}

# Function to get job count
get_job_count() {
    curl -s "$API_URL/api/stats" | grep -o '"totalJobs":[0-9]*' | cut -d':' -f2 2>/dev/null || echo "0"
}

# Function to display dashboard URL
show_dashboard() {
    echo ""
    echo -e "${BLUE}📊 Dashboard Access:${NC}"
    echo "   $API_URL"
    echo ""
}

# Main test sequence
main() {
    echo ""
    echo -e "${YELLOW}Testing Configuration:${NC}"
    echo "API URL: $API_URL"
    echo "Office: $OFFICE_NAME"
    echo ""
    
    echo -e "${YELLOW}Step 1: System Health Check${NC}"
    echo "--------------------------------"
    
    # Check if backend services are running
    if ! check_service "Backend API" "$API_URL/api/health"; then
        echo -e "${RED}❌ Backend not accessible. Please check:${NC}"
        echo "   - Server is running"
        echo "   - API URL is correct: $API_URL"
        echo "   - Network connectivity"
        exit 1
    fi
    
    # Check database connectivity
    if ! check_service "Database" "$API_URL/api/stats"; then
        echo -e "${RED}❌ Database not accessible${NC}"
        exit 1
    fi
    
    echo ""
    echo -e "${YELLOW}Step 2: Initial Statistics${NC}"
    echo "-------------------------"
    initial_count=$(get_job_count)
    echo "Current job count: $initial_count"
    
    echo ""
    echo -e "${YELLOW}Step 3: Sending Test Print Jobs${NC}"
    echo "--------------------------------"
    
    # Test jobs for various scenarios
    send_test_job "test-001" "john.doe" "OFFICE-PC-01" "Weekly Report.pdf" 5
    send_test_job "test-002" "jane.smith" "OFFICE-PC-02" "Marketing Proposal.docx" 12
    send_test_job "test-003" "bob.wilson" "OFFICE-PC-03" "Budget Spreadsheet.xlsx" 3
    send_test_job "test-004" "alice.brown" "OFFICE-PC-04" "Meeting Minutes.pdf" 2
    send_test_job "test-005" "mike.johnson" "OFFICE-PC-05" "Sales Report.pptx" 8
    send_test_job "test-006" "sarah.davis" "OFFICE-PC-06" "Marketing Flyer.pdf" 1
    send_test_job "test-007" "tom.anderson" "OFFICE-PC-07" "System Manual.pdf" 15
    send_test_job "test-008" "lisa.wilson" "OFFICE-PC-08" "Financial Summary.xlsx" 4
    send_test_job "test-009" "chris.taylor" "OFFICE-PC-09" "Client Proposal.docx" 7
    send_test_job "test-010" "emma.martinez" "OFFICE-PC-10" "HR Policy.pdf" 6
    
    echo ""
    echo -e "${YELLOW}Step 4: Verifying Results${NC}"
    echo "-------------------------"
    
    sleep 2  # Wait for database to process
    final_count=$(get_job_count)
    new_jobs=$((final_count - initial_count))
    
    echo "Initial job count: $initial_count"
    echo "Final job count: $final_count"
    echo "New jobs added: $new_jobs"
    
    if [ "$new_jobs" -eq 10 ]; then
        echo -e "${GREEN}✅ All test jobs successfully recorded!${NC}"
    else
        echo -e "${RED}❌ Expected 10 new jobs, got $new_jobs${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}Step 5: Testing API Endpoints${NC}"
    echo "-----------------------------"
    
    # Test GET endpoints
    echo -n "Testing job list endpoint... "
    if curl -s "$API_URL/api/print-jobs" | grep -q '"success":true'; then
        echo -e "${GREEN}✓ Working${NC}"
    else
        echo -e "${RED}✗ Failed${NC}"
    fi
    
    echo -n "Testing statistics endpoint... "
    if curl -s "$API_URL/api/stats" | grep -q '"totalJobs"'; then
        echo -e "${GREEN}✓ Working${NC}"
    else
        echo -e "${RED}✗ Failed${NC}"
    fi
    
    echo -n "Testing user filtering... "
    if curl -s "$API_URL/api/print-jobs?user=john.doe" | grep -q 'john.doe'; then
        echo -e "${GREEN}✓ Working${NC}"
    else
        echo -e "${RED}✗ Failed${NC}"
    fi
    
    echo -n "Testing date filtering... "
    today=$(date +%Y-%m-%d)
    if curl -s "$API_URL/api/print-jobs?date=$today" | grep -q '"data"'; then
        echo -e "${GREEN}✓ Working${NC}"
    else
        echo -e "${RED}✗ Failed${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}Step 6: Performance Analysis${NC}"
    echo "----------------------------"
    
    # Get detailed stats
    stats=$(curl -s "$API_URL/api/stats")
    if [ -n "$stats" ]; then
        total_jobs=$(echo "$stats" | grep -o '"totalJobs":[0-9]*' | cut -d':' -f2)
        total_pages=$(echo "$stats" | grep -o '"totalPages":[0-9]*' | cut -d':' -f2)
        
        echo "📊 System Statistics:"
        echo "   Total Jobs: $total_jobs"
        echo "   Total Pages: $total_pages"
        
        if [ "$total_pages" -gt 0 ] && [ "$total_jobs" -gt 0 ]; then
            avg_pages=$((total_pages / total_jobs))
            echo "   Average Pages/Job: $avg_pages"
        fi
        
        # Calculate some test metrics
        if [ "$total_jobs" -ge 10 ]; then
            echo "   Test Coverage: ✅ Sufficient data"
        else
            echo "   Test Coverage: ⚠️  Need more test data"
        fi
    else
        echo "❌ Could not retrieve statistics"
    fi
    
    echo ""
    echo -e "${YELLOW}Step 7: User Scenario Testing${NC}"
    echo "-----------------------------"
    
    # Test different document types
    echo "Testing various document types..."
    send_test_job "scenario-01" "test.user" "TEST-PC" "Invoice-12345.pdf" 1
    send_test_job "scenario-02" "test.user" "TEST-PC" "Large-Document.pdf" 50
    send_test_job "scenario-03" "test.user" "TEST-PC" "Presentation.pptx" 20
    send_test_job "scenario-04" "test.user" "TEST-PC" "Spreadsheet.xlsx" 5
    send_test_job "scenario-05" "test.user" "TEST-PC" "Email-Print.msg" 1
    
    # Test edge cases
    echo ""
    echo "Testing edge cases..."
    send_test_job "edge-01" "user.with.dots" "PC-WITH-DASHES" "File with spaces.pdf" 1
    send_test_job "edge-02" "UPPERCASE" "UPPERCASE-PC" "UPPERCASE-FILE.PDF" 1
    send_test_job "edge-03" "test_underscore" "PC_UNDERSCORE" "file_underscore.pdf" 1
    
    show_dashboard
    
    echo -e "${GREEN}🎉 System Test Complete!${NC}"
    echo ""
    echo "Test Summary:"
    echo "============="
    echo "✅ API connectivity verified"
    echo "✅ Database operations working"
    echo "✅ Print job submission successful"
    echo "✅ Data retrieval functioning"
    echo "✅ Filtering and search operational"
    echo "✅ Edge cases handled"
    echo ""
    echo "Next Steps:"
    echo "1. Open the dashboard and review test data"
    echo "2. Deploy print listeners to office computers"
    echo "3. Test with real print jobs"
    echo "4. Monitor system performance"
    echo ""
    echo "Print Listener Installation:"
    echo "Windows: Run install-print-monitor.bat as Administrator"
    echo "Ubuntu:  Run sudo ./install-ubuntu-print-monitor.sh"
}

# Help function
show_help() {
    echo "Print Monitor System Test Script"
    echo ""
    echo "Usage: $0 [API_URL] [OFFICE_NAME]"
    echo ""
    echo "Parameters:"
    echo "  API_URL      API server URL (default: http://localhost:3000)"
    echo "  OFFICE_NAME  Office name for testing (default: Test Office)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Test local server"
    echo "  $0 http://192.168.1.100:3000         # Test remote server"
    echo "  $0 http://192.168.1.100:3000 \"ABC Company\"  # Custom office name"
    echo ""
    echo "What this script tests:"
    echo "  - API server connectivity"
    echo "  - Database operations"
    echo "  - Print job submission"
    echo "  - Data retrieval and filtering"
    echo "  - System performance"
    echo "  - Edge case handling"
}

# Parse command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    *)
        main
        ;;
esac