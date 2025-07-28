#!/bin/bash

# Configuration
API_KEY="123456-123456-123456-123456-123456"
BASE_URL="https://maildocker.domain/api/v1"
ADD_API_URL="${BASE_URL}/add/alias"
EDIT_API_URL="${BASE_URL}/edit/alias"
GET_API_URL="${BASE_URL}/get/alias/all"
INPUT_FILE="${1:-aliases.json}"
LOG_FILE="alias_import_$(date +%Y%m%d_%H%M%S).log"

# Help message
function show_help {
    echo "Usage: $0 [input_file.json]"
    echo ""
    echo "This script imports email aliases from a JSON file to the mail server API."
    echo ""
    echo "Features:"
    echo "  - Checks for existing aliases before creating new ones"
    echo "  - Updates existing aliases if they already exist"
    echo "  - Logs all operations with timestamps"
    echo "  - Provides summary statistics"
    echo ""
    echo "Requirements:"
    echo "  - jq must be installed for JSON processing"
    echo "  - curl for API communication"
    echo ""
    echo "Example JSON format (one per line):"
    echo '"{"active": "1", "address": "alias@domain.com", "goto": "real@domain.com,real1@otherdomain"}"'
    echo ""
    echo "For questions or support contact: enriluis@gmail.com"
    echo ""
    echo "Acknowledgments:"
    echo "  Thanks to the developers of jq and curl for these essential tools."
}

# Check for help request
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
    exit 0
fi

# Check jq
if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is not installed. Install with:"
    echo "  Ubuntu/Debian: sudo apt install jq"
    echo "  CentOS/RHEL: sudo yum install jq"
    exit 1
fi

# Check input file
if [ ! -f "$INPUT_FILE" ]; then
    echo "ERROR: File $INPUT_FILE not found"
    exit 1
fi

# Counters
total=0
created=0
updated=0
failed=0
existing=0

# Get list of existing aliases
echo "Fetching list of existing aliases..." | tee -a "$LOG_FILE"
existing_aliases=$(curl -s \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: ${API_KEY}" \
  -X GET \
  "${GET_API_URL}")

if [ $? -ne 0 ]; then
    echo "ERROR: Could not retrieve existing aliases list" | tee -a "$LOG_FILE"
    exit 1
fi

echo "=== Import started: $(date) ===" | tee -a "$LOG_FILE"

# Process file
while read -r line; do
    ((total++))
    
    # Clean and validate JSON
    json=$(echo "$line" | sed 's/^"//;s/"$//' | jq -c . 2>/dev/null)
    
    if [ -z "$json" ]; then
        echo "ERROR: Line $total - Invalid JSON: $line" | tee -a "$LOG_FILE"
        ((failed++))
        continue
    fi
    
    address=$(echo "$json" | jq -r '.address')
    goto=$(echo "$json" | jq -r '.goto')
    active=$(echo "$json" | jq -r '.active // "1"')
    public_comment=$(echo "$json" | jq -r '.public_comment // ""')
    private_comment=$(echo "$json" | jq -r '.private_comment // ""')
    
    echo "Processing ($total): $address → $goto" | tee -a "$LOG_FILE"
    
    # Check if alias exists
    alias_id=$(echo "$existing_aliases" | jq -r --arg addr "$address" '.[] | select(.address == $addr) | .id')
    
    if [ -n "$alias_id" ]; then
        echo "  Alias already exists (ID: $alias_id), updating..." | tee -a "$LOG_FILE"
        
        # Prepare update data (correct format for jq)
        update_data=$(jq -n \
          --arg active "$active" \
          --arg address "$address" \
          --arg goto "$goto" \
          --arg private_comment "$private_comment" \
          --arg public_comment "$public_comment" \
          --argjson alias_id "$alias_id" \
          '{
            "attr": {
              "active": $active,
              "address": $address,
              "goto": $goto,
              "private_comment": $private_comment,
              "public_comment": $public_comment
            },
            "items": [$alias_id]
          }')
        
        # Show update data for debugging
        echo "  Update data:" | tee -a "$LOG_FILE"
        echo "$update_data" | jq . | tee -a "$LOG_FILE"
        
        # Update alias
        response=$(curl -s -i \
          -H "Accept: application/json" \
          -H "Content-Type: application/json" \
          -H "X-API-Key: ${API_KEY}" \
          -X POST \
          -d "$update_data" \
          "${EDIT_API_URL}" 2>&1)
        
        # Log response
        echo "$response" >> "$LOG_FILE"
        
        # Check response
        if echo "$response" | grep -q "HTTP/.* 200"; then
            echo "  ✓ Update successful" | tee -a "$LOG_FILE"
            ((updated++))
        else
            echo "  ✖ Update failed" | tee -a "$LOG_FILE"
            echo "  Details:" | tee -a "$LOG_FILE"
            echo "$response" | grep "{" | jq . | tee -a "$LOG_FILE"
            ((failed++))
        fi
        
    else
        # Create new alias
        echo "  Alias doesn't exist, creating..." | tee -a "$LOG_FILE"
        
        response=$(curl -s -i \
          -H "Accept: application/json" \
          -H "Content-Type: application/json" \
          -H "X-API-Key: ${API_KEY}" \
          -X POST \
          -d "$json" \
          "${ADD_API_URL}" 2>&1)
        
        # Log response
        echo "$response" >> "$LOG_FILE"
        
        # Check response
        if echo "$response" | grep -q "HTTP/.* 200"; then
            echo "  ✓ Creation successful" | tee -a "$LOG_FILE"
            ((created++))
        else
            echo "  ✖ Creation failed" | tee -a "$LOG_FILE"
            echo "  Details:" | tee -a "$LOG_FILE"
            echo "$response" | grep "{" | jq . | tee -a "$LOG_FILE"
            ((failed++))
        fi
    fi
    
    sleep 0.5
    
done < <(grep -v '^$' "$INPUT_FILE")

# Summary
echo "" | tee -a "$LOG_FILE"
echo "=== Summary ===" | tee -a "$LOG_FILE"
echo "Total processed: $total" | tee -a "$LOG_FILE"
echo "Aliases created: $created" | tee -a "$LOG_FILE"
echo "Aliases updated: $updated" | tee -a "$LOG_FILE"
echo "Failures: $failed" | tee -a "$LOG_FILE"
echo "=== End: $(date) ===" | tee -a "$LOG_FILE"

echo "Details in: $LOG_FILE"