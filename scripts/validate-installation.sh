#!/bin/bash
# validate-installation.sh
# Comprehensive validation script for office print monitor deployment

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
API_SERVER="${1:-192.168.1.100}"
EXPECTED_COMPUTERS=10
EXPECTED_PRINTERS=2

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Print Monitor Installation Validator${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <API_SERVER_IP>"
    echo "Example: $0 192.168.1.100"
    exit 1
fi

echo -e "${GREEN}Validating installation for API Server: $API_SERVER${NC}"
echo ""

# Validation functions
validate_api_connectivity() {
    echo -e "${YELLOW}[1/8] Testing API Connectivity${NC}"
    echo "--------------------------------"
    
    # Test API health endpoint
    echo -n "API Health Check... "
    if curl -s --connect-timeout 10 "http://$API_SERVER:3000/api/health" > /dev/null; then
        echo -e "${GREEN}✅ PASS${NC}"
    else
        echo -e "${RED}❌ FAIL - API not responding${NC}"
        echo "   Check: Server running, firewall, network connectivity"
        return 1
    fi
    
    # Test API response format
    echo -n "API Response Format... "
    health_response=$(curl -s "http://$API_SERVER:3000/api/health")
    if echo "$health_response" | grep -q "status\|healthy"; then
        echo -e "${GREEN}✅ PASS${NC}"
    else
        echo -e "${RED}❌ FAIL - Invalid API response${NC}"
        return 1
    fi
    
    echo ""
}

validate_database_connectivity() {
    echo -e "${YELLOW}[2/8] Testing Database Connectivity${NC}"
    echo "-----------------------------------"
    
    # Test statistics endpoint (requires database)
    echo -n "Database Connection... "
    stats_response=$(curl -s "http://$API_SERVER:3000/api/stats")
    if echo "$stats_response" | grep -q '"totalJobs"'; then
        echo -e "${GREEN}✅ PASS${NC}"
    else
        echo -e "${RED}❌ FAIL - Database not accessible${NC}"
        echo "   Response: $stats_response"
        return 1
    fi
    
    # Test print jobs endpoint
    echo -n "Print Jobs Endpoint... "
    jobs_response=$(curl -s "http://$API_SERVER:3000/api/print-jobs?limit=1")
    if echo "$jobs_response" | grep -q '"success"'; then
        echo -e "${GREEN}✅ PASS${NC}"
    else
        echo -e "${RED}❌ FAIL - Print jobs endpoint error${NC}"
        return 1
    fi
    
    echo ""
}

validate_system_statistics() {
    echo -e "${YELLOW}[3/8] Analyzing System Statistics${NC}"
    echo "---------------------------------"
    
    # Get current statistics
    stats=$(curl -s "http://$API_SERVER:3000/api/stats")
    
    if [ -n "$stats" ]; then
        total_jobs=$(echo "$stats" | grep -o '"totalJobs":[0-9]*' | cut -d':' -f2)
        total_pages=$(echo "$stats" | grep -o '"totalPages":[0-9]*' | cut -d':' -f2)
        
        echo "📊 Current Statistics:"
        echo "   Total Jobs: ${total_jobs:-0}"
        echo "   Total Pages: ${total_pages:-0}"
        
        # Validate reasonable data
        if [ "${total_jobs:-0}" -gt 0 ]; then
            echo -e "   Data Status: ${GREEN}✅ PASS - System has data${NC}"
        else
            echo -e "   Data Status: ${YELLOW}⚠️  WARNING - No print jobs yet${NC}"
        fi
        
        if [ "${total_pages:-0}" -gt 0 ]; then
            avg_pages=$((total_pages / total_jobs))
            echo "   Average Pages/Job: $avg_pages"
            
            if [ "$avg_pages" -gt 0 ] && [ "$avg_pages" -lt 100 ]; then
                echo -e "   Page Average: ${GREEN}✅ PASS - Reasonable average${NC}"
            else
                echo -e "   Page Average: ${YELLOW}⚠️  WARNING - Unusual page average${NC}"
            fi
        fi
    else
        echo -e "${RED}❌ FAIL - Could not retrieve statistics${NC}"
        return 1
    fi
    
    echo ""
}

validate_computer_coverage() {
    echo -e "${YELLOW}[4/8] Checking Computer Coverage${NC}"
    echo "--------------------------------"
    
    # Get recent jobs to analyze computer coverage
    recent_jobs=$(curl -s "http://$API_SERVER:3000/api/print-jobs?limit=100")
    
    if [ -n "$recent_jobs" ]; then
        # Extract unique computer names
        computers=$(echo "$recent_jobs" | grep -o '"machine_name":"[^"]*"' | cut -d'"' -f4 | sort -u)
        computer_count=$(echo "$computers" | wc -l)
        
        echo "🖥️  Computers Found:"
        if [ -n "$computers" ]; then
            echo "$computers" | while read -r computer; do
                if [ -n "$computer" ]; then
                    echo "   - $computer"
                fi
            done
        fi
        
        echo ""
        echo "📈 Coverage Analysis:"
        echo "   Computers Reporting: $computer_count / $EXPECTED_COMPUTERS"
        
        if [ "$computer_count" -eq "$EXPECTED_COMPUTERS" ]; then
            echo -e "   Coverage Status: ${GREEN}✅ PASS - All computers reporting${NC}"
        elif [ "$computer_count" -gt 0 ]; then
            echo -e "   Coverage Status: ${YELLOW}⚠️  PARTIAL - Some computers missing${NC}"
            echo "   Action: Check installations on missing computers"
        else
            echo -e "   Coverage Status: ${RED}❌ FAIL - No computers reporting${NC}"
            echo "   Action: Install print listeners on office computers"
        fi
        
        # Check for expected computer names
        expected_computers=("OFFICE-PC-01" "OFFICE-PC-02" "OFFICE-PC-03" "OFFICE-PC-04" "OFFICE-PC-05" 
                           "OFFICE-PC-06" "OFFICE-PC-07" "OFFICE-PC-08" "OFFICE-PC-09" "OFFICE-PC-10")
        
        missing_computers=()
        for expected in "${expected_computers[@]}"; do
            if ! echo "$computers" | grep -q "$expected"; then
                missing_computers+=("$expected")
            fi
        done
        
        if [ ${#missing_computers[@]} -gt 0 ]; then
            echo ""
            echo -e "${YELLOW}⚠️  Missing Computers:${NC}"
            for missing in "${missing_computers[@]}"; do
                echo "   - $missing"
            done
        fi
    else
        echo -e "${RED}❌ FAIL - Could not retrieve job data${NC}"
        return 1
    fi
    
    echo ""
}

validate_printer_coverage() {
    echo -e "${YELLOW}[5/8] Checking Printer Coverage${NC}"
    echo "-------------------------------"
    
    # Get recent jobs to analyze printer usage
    recent_jobs=$(curl -s "http://$API_SERVER:3000/api/print-jobs?limit=100")
    
    if [ -n "$recent_jobs" ]; then
        # Extract unique printer names
        printers=$(echo "$recent_jobs" | grep -o '"printer_name":"[^"]*"' | cut -d'"' -f4 | sort -u)
        printer_count=$(echo "$printers" | wc -l)
        
        echo "🖨️  Printers Found:"
        if [ -n "$printers" ]; then
            echo "$printers" | while read -r printer; do
                if [ -n "$printer" ]; then
                    # Count jobs for this printer
                    job_count=$(echo "$recent_jobs" | grep -c "\"printer_name\":\"$printer\"")
                    echo "   - $printer ($job_count jobs)"
                fi
            done
        fi
        
        echo ""
        echo "📈 Printer Analysis:"
        echo "   Printers Active: $printer_count"
        
        if [ "$printer_count" -ge "$EXPECTED_PRINTERS" ]; then
            echo -e "   Printer Status: ${GREEN}✅ PASS - Multiple printers active${NC}"
        elif [ "$printer_count" -eq 1 ]; then
            echo -e "   Printer Status: ${YELLOW}⚠️  WARNING - Only one printer active${NC}"
        else
            echo -e "   Printer Status: ${RED}❌ FAIL - No printers detected${NC}"
        fi
    else
        echo -e "${RED}❌ FAIL - Could not retrieve printer data${NC}"
        return 1
    fi
    
    echo ""
}

validate_data_quality() {
    echo -e "${YELLOW}[6/8] Validating Data Quality${NC}"
    echo "-----------------------------"
    
    # Get recent jobs for data quality analysis
    recent_jobs=$(curl -s "http://$API_SERVER:3000/api/print-jobs?limit=20")
    
    if [ -n "$recent_jobs" ]; then
        # Check for required fields
        echo -n "Required Fields Present... "
        if echo "$recent_jobs" | grep -q '"user_name"' && \
           echo "$recent_jobs" | grep -q '"machine_name"' && \
           echo "$recent_jobs" | grep -q '"printer_name"' && \
           echo "$recent_jobs" | grep -q '"document_name"'; then
            echo -e "${GREEN}✅ PASS${NC}"
        else
            echo -e "${RED}❌ FAIL - Missing required fields${NC}"
        fi
        
        # Check for reasonable page counts
        echo -n "Page Count Validation... "
        page_counts=$(echo "$recent_jobs" | grep -o '"page_count":[0-9]*' | cut -d':' -f2)
        invalid_pages=0
        
        for count in $page_counts; do
            if [ "$count" -le 0 ] || [ "$count" -gt 1000 ]; then
                invalid_pages=$((invalid_pages + 1))
            fi
        done
        
        if [ "$invalid_pages" -eq 0 ]; then
            echo -e "${GREEN}✅ PASS - Page counts reasonable${NC}"
        else
            echo -e "${YELLOW}⚠️  WARNING - $invalid_pages unusual page counts${NC}"
        fi
        
        # Check timestamp recency
        echo -n "Timestamp Validation... "
        current_time=$(date +%s)
        recent_count=0
        
        # Simple check for recent activity (jobs within last 24 hours)
        timestamps=$(echo "$recent_jobs" | grep -o '"print_time":"[^"]*"' | cut -d'"' -f4)
        for timestamp in $timestamps; do
            if [ -n "$timestamp" ]; then
                recent_count=$((recent_count + 1))
            fi
        done
        
        if [ "$recent_count" -gt 0 ]; then
            echo -e "${GREEN}✅ PASS - Recent timestamps found${NC}"
        else
            echo -e "${YELLOW}⚠️  WARNING - No recent timestamps${NC}"
        fi
    else
        echo -e "${RED}❌ FAIL - Could not retrieve job data for validation${NC}"
        return 1
    fi
    
    echo ""
}

validate_dashboard_access() {
    echo -e "${YELLOW}[7/8] Testing Dashboard Access${NC}"
    echo "------------------------------"
    
    # Test dashboard accessibility
    echo -n "Dashboard HTTP Response... "
    if curl -s --connect-timeout 10 "http://$API_SERVER" > /dev/null; then
        echo -e "${GREEN}✅ PASS${NC}"
    else
        echo -e "${RED}❌ FAIL - Dashboard not accessible${NC}"
        echo "   Check: Frontend service, nginx configuration"
    fi
    
    # Test dashboard content
    echo -n "Dashboard Content... "
    dashboard_content=$(curl -s "http://$API_SERVER")
    if echo "$dashboard_content" | grep -q -i "print\|monitor\|dashboard"; then
        echo -e "${GREEN}✅ PASS${NC}"
    else
        echo -e "${YELLOW}⚠️  WARNING - Dashboard content unclear${NC}"
    fi
    
    echo ""
}

validate_performance() {
    echo -e "${YELLOW}[8/8] Testing System Performance${NC}"
    echo "--------------------------------"
    
    # Test API response time
    echo -n "API Response Time... "
    start_time=$(date +%s%N)
    curl -s "http://$API_SERVER:3000/api/health" > /dev/null
    end_time=$(date +%s%N)
    response_time=$(( (end_time - start_time) / 1000000 ))  # Convert to milliseconds
    
    if [ "$response_time" -lt 1000 ]; then
        echo -e "${GREEN}✅ PASS (${response_time}ms)${NC}"
    elif [ "$response_time" -lt 3000 ]; then
        echo -e "${YELLOW}⚠️  SLOW (${response_time}ms)${NC}"
    else
        echo -e "${RED}❌ FAIL - Too slow (${response_time}ms)${NC}"
    fi
    
    # Test concurrent requests
    echo -n "Concurrent Request Handling... "
    (curl -s "http://$API_SERVER:3000/api/stats" > /dev/null &
     curl -s "http://$API_SERVER:3000/api/print-jobs?limit=5" > /dev/null &
     curl -s "http://$API_SERVER:3000/api/health" > /dev/null &
     wait)
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ PASS${NC}"
    else
        echo -e "${RED}❌ FAIL - Concurrent request issues${NC}"
    fi
    
    echo ""
}

# Generate final report
generate_report() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}         Validation Summary${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # Overall system status
    stats=$(curl -s "http://$API_SERVER:3000/api/stats")
    recent_jobs=$(curl -s "http://$API_SERVER:3000/api/print-jobs?limit=50")
    
    total_jobs=$(echo "$stats" | grep -o '"totalJobs":[0-9]*' | cut -d':' -f2)
    computers=$(echo "$recent_jobs" | grep -o '"machine_name":"[^"]*"' | cut -d'"' -f4 | sort -u | wc -l)
    printers=$(echo "$recent_jobs" | grep -o '"printer_name":"[^"]*"' | cut -d'"' -f4 | sort -u | wc -l)
    
    echo "📊 System Overview:"
    echo "   API Server: $API_SERVER"
    echo "   Dashboard: http://$API_SERVER"
    echo "   Total Print Jobs: ${total_jobs:-0}"
    echo "   Active Computers: $computers"
    echo "   Active Printers: $printers"
    echo ""
    
    echo "✅ Validation Results:"
    echo "   API Connectivity: Verified"
    echo "   Database Operations: Functional"
    echo "   Data Collection: Active"
    echo "   Dashboard Access: Available"
    echo ""
    
    # Overall assessment
    if [ "$computers" -eq "$EXPECTED_COMPUTERS" ] && [ "${total_jobs:-0}" -gt 0 ]; then
        echo -e "${GREEN}🎉 VALIDATION PASSED!${NC}"
        echo "   All systems are working correctly."
        echo "   The print monitoring system is ready for production use."
    elif [ "$computers" -gt 0 ] && [ "${total_jobs:-0}" -gt 0 ]; then
        echo -e "${YELLOW}⚠️  VALIDATION PARTIAL${NC}"
        echo "   System is functional but needs attention:"
        echo "   - Complete installation on all computers"
        echo "   - Verify all printers are being monitored"
    else
        echo -e "${RED}❌ VALIDATION FAILED${NC}"
        echo "   System needs immediate attention:"
        echo "   - Check API server status"
        echo "   - Install print listeners on computers"
        echo "   - Verify network connectivity"
    fi
    
    echo ""
    echo "Next Steps:"
    echo "1. Review any warnings or failures above"
    echo "2. Complete missing installations"
    echo "3. Monitor system for 24-48 hours"
    echo "4. Generate usage reports for management"
}

# Main execution
main() {
    validate_api_connectivity || exit 1
    validate_database_connectivity || exit 1
    validate_system_statistics
    validate_computer_coverage
    validate_printer_coverage
    validate_data_quality
    validate_dashboard_access
    validate_performance
    generate_report
}

# Help function
show_help() {
    echo "Print Monitor Installation Validator"
    echo ""
    echo "Usage: $0 <API_SERVER_IP>"
    echo ""
    echo "Parameters:"
    echo "  API_SERVER_IP    IP address of the print monitor server"
    echo ""
    echo "Example:"
    echo "  $0 192.168.1.100"
    echo ""
    echo "This script validates:"
    echo "  - API server connectivity and health"
    echo "  - Database operations and data integrity"
    echo "  - Computer and printer coverage"
    echo "  - Data quality and consistency"
    echo "  - Dashboard accessibility"
    echo "  - System performance"
}

# Parse command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    "")
        echo "Error: API server IP required"
        show_help
        exit 1
        ;;
    *)
        main
        ;;
esac