#!/bin/bash

###############################################################
# Mailcow Sieve Filter Manager
# Version: 1.2
# Author: Enri Luis <enriluis@gmail.com>
# Description: Automates creation/update of Sieve filters in Mailcow
#              with strict alias validation - only creates filters
#              when the alias exists.
###############################################################

### REQUIREMENTS ###
# 1. Mailcow environment with docker
# 2. Access to Mailcow's MySQL database
# 3. CSV file with email accounts to process
# 4. Properly configured aliases in Mailcow

### USAGE ###
# ./sieve_filter_manager.sh [-h|--help]
# 
# Options:
#   -h, --help    Show this help message

### CONFIGURATION ###
MAILCOW_DIR="/docker-mail-mtc"
CONFIG_FILE="${MAILCOW_DIR}/mailcow.conf"
INPUT_FILE="${MAILCOW_DIR}/helper-scripts/address_aliases.csv"
LOG_FILE="/tmp/sieve_filters_$(date +%Y%m%d_%H%M%S).log"

# Display help information
#!/bin/bash

###############################################################
# Mailcow Sieve Filter Manager
# Version: 1.3
# Author: Enri Luis <enriluis@gmail.com>
# Repository: https://github.com/enriluis/mailcow-sieve-manager
# Description: Advanced mail routing solution for Mailcow
###############################################################

### CONFIGURATION ###
MAILCOW_DIR="/docker-mail-mtc"
CONFIG_FILE="${MAILCOW_DIR}/mailcow.conf"
INPUT_FILE="${MAILCOW_DIR}/helper-scripts/address_aliases.csv"
LOG_FILE="/tmp/sieve_filters_$(date +%Y%m%d_%H%M%S).log"

show_help() {
    cat <<EOF
Mailcow Sieve Filter Manager - Advanced Mail Routing Solution

USAGE:
  $0 [options]

OPTIONS:
  -h, --help    Display this help message

DESCRIPTION:
  This script automates Sieve filter management in Mailcow to implement
  a complete mail routing system that includes:

  1. Redirection to multiple recipients (via aliases)
  2. Subject modification for redirected messages
  3. Message flagging as high priority
  4. Automatic configuration validation

  KEY DIFFERENCES FROM POSTFIXADMIN:
  * Mailcow requires aliases + Sieve filters for multi-recipient routing
  * Postfixadmin allows direct forwarding in account settings
  * This script adds functionality not available in Mailcow's UI:
    - Subject modification ([PREFIX] Original Subject)
    - Automatic importance flagging (High Priority)
    - Configuration validation

REQUIREMENTS:
  - Mailcow environment with Docker
  - CSV file with accounts to process
  - Preconfigured aliases in Mailcow

CONFIGURATION:
  Input file: ${INPUT_FILE}
  Log file: ${LOG_FILE}

EXAMPLE CSV:
  user1@domain.com
  user2@domain.com

For more details and use cases, visit:
https://github.com/enriluis/mailcow-sieve-manager

Support: enriluis@gmail.com
EOF
    exit 0
}

# [...] (rest of the script remains the same)

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            ;;
        *)
            echo "Error: Unknown option $1"
            show_help
            exit 1
            ;;
    esac
done

# Load Mailcow environment variables
if [[ -f ${CONFIG_FILE} ]]; then
    source ${CONFIG_FILE}
else
    echo "ERROR: Mailcow configuration file not found at ${CONFIG_FILE}" | tee -a ${LOG_FILE}
    exit 1
fi

# Verify input file exists
if [[ ! -f ${INPUT_FILE} ]]; then
    echo "ERROR: Input CSV file not found at ${INPUT_FILE}" | tee -a ${LOG_FILE}
    exit 1
fi

# Database configuration
DB_HOST="${DBHOST:-mysql}"
DB_NAME="${DBNAME:-mailcow}"
DB_USER="${DBUSER:-mailcow}"
DB_PASS="${DBPASS}"

# Verify database credentials
if [[ -z "${DB_PASS}" ]]; then
    echo "ERROR: Database password not configured in mailcow.conf" | tee -a ${LOG_FILE}
    exit 1
fi

### FUNCTIONS ###

# Log messages with timestamp
log() {
    local message="$1"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ${message}" | tee -a ${LOG_FILE}
}

# Execute MySQL query through docker
execute_mysql_query() {
    local query="$1"
    local result
    
    result=$(docker compose -f "${MAILCOW_DIR}/docker-compose.yml" exec -T mysql-mailcow \
        mysql -N -u"${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" -e "${query}" 2>&1)
    local exit_code=$?
    
    if [[ ${exit_code} -ne 0 ]]; then
        log "MySQL ERROR (Code ${exit_code})"
        log "Failed query: ${query}"
        log "Error details: ${result}"
        return 1
    fi
    
    echo "${result}"
    return 0
}

# Check if mailbox exists
validate_mailbox_exists() {
    local email_address="$1"
    local query="SELECT COUNT(*) FROM mailbox WHERE username = '${email_address}';"
    local count
    
    count=$(execute_mysql_query "${query}")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    count=$(echo "${count}" | tr -d '[:space:]')
    [[ "${count}" =~ ^[0-9]+$ ]] && [[ ${count} -gt 0 ]]
}

# Check if alias exists
validate_alias_exists() {
    local alias_email="$1"
    local query="SELECT COUNT(*) FROM alias WHERE address = '${alias_email}';"
    local count
    
    count=$(execute_mysql_query "${query}")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    count=$(echo "${count}" | tr -d '[:space:]')
    [[ "${count}" =~ ^[0-9]+$ ]] && [[ ${count} -gt 0 ]]
}

# Generate Sieve script with required redirect
generate_sieve_script() {
    local email_address="$1"
    local alias_email="$2"
    local prefix=$(echo "${email_address}" | cut -d'@' -f1 | tr '[:lower:]' '[:upper:]')

    cat <<EOF
require "editheader";
require "variables";
require "reject";
require "imap4flags";
if address :matches ["to", "cc"] "${email_address}" {
    # === Subject Modification ===
    # Option 1: When original Subject exists
    if header :matches "Subject" "*" {
        addheader :last "Subject" "[${prefix}] \${1}";
        addflag "\$label1";
    }
    # Option 2: When no Subject exists
    else {
        addheader :last "Subject" "[${prefix}]";
        addflag "\$label1";
    }
    # === Mark as Important ===
    addflag "\\\\Flagged";
    addflag "\$label1";
    addheader "Importance" "high";
    addheader "X-Priority" "1";
    addflag "\$label1";
    addheader "Priority" "urgent";
    # === Routing ===
    redirect "${alias_email}";
}
EOF
}

# Escape strings for SQL
escape_sql_string() {
    local string="$1"
    echo "${string}" | sed -e "s/'/''/g" -e 's/\\/\\\\/g'
}

### MAIN SCRIPT EXECUTION ###

log "Starting Sieve filter management process"
log "Processing accounts from: ${INPUT_FILE}"

# Verify database connectivity
mailbox_count=$(execute_mysql_query "SELECT COUNT(*) FROM mailbox;")
alias_count=$(execute_mysql_query "SELECT COUNT(*) FROM alias;")

log "Total mailboxes found: ${mailbox_count}"
log "Total aliases configured: ${alias_count}"

# Process each account from CSV file
while IFS= read -r email_address || [[ -n "${email_address}" ]]; do
    # Clean and validate email address
    email_address=$(echo "${email_address}" | tr -d '\r\n' | xargs)
    [[ -z "${email_address}" || "${email_address}" == \#* ]] && continue
    
    if [[ ! "${email_address}" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        log "SKIPPED: Invalid email format '${email_address}'"
        continue
    fi
    
    log "Processing account: '${email_address}'"
    
    # Validate mailbox exists
    if ! validate_mailbox_exists "${email_address}"; then
        log "ERROR: Mailbox '${email_address}' not found in database - skipping"
        continue
    fi
    
    # Generate alias email
    prefix=$(echo "${email_address}" | cut -d'@' -f1 | tr '[:lower:]' '[:upper:]')
    alias_email="$(echo "${prefix}" | tr '[:upper:]' '[:lower:]')_alias@$(echo "${email_address}" | cut -d'@' -f2 | tr '[:upper:]' '[:lower:]')"
    
    # Validate alias exists - SKIP ENTIRE PROCESS IF NOT
    if ! validate_alias_exists "${alias_email}"; then
        log "SKIPPED: Required alias '${alias_email}' not found - no filter created"
        continue
    fi
    
    log "SUCCESS: Valid alias found at '${alias_email}' - proceeding with filter creation"
    
    # Generate Sieve script
    sieve_script=$(generate_sieve_script "${email_address}" "${alias_email}")
    script_description="${prefix} REDIRECT"
    
    # Prepare values for SQL
    escaped_email=$(escape_sql_string "${email_address}")
    escaped_description=$(escape_sql_string "${script_description}")
    escaped_script=$(escape_sql_string "${sieve_script}")
    
    current_timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    # Check if filter already exists
    CHECK_QUERY="SELECT COUNT(*) FROM sieve_filters WHERE username = '${escaped_email}' AND filter_type = 'prefilter';"
    existing_count=$(execute_mysql_query "${CHECK_QUERY}")
    
    if [[ ${existing_count} -gt 0 ]]; then
        # Update existing filter
        UPDATE_QUERY="UPDATE sieve_filters SET 
            script_desc = '${escaped_description}',
            script_data = '${escaped_script}',
            script_name = 'active',
            modified = '${current_timestamp}'
            WHERE username = '${escaped_email}' AND filter_type = 'prefilter';"
        
        log "Updating existing filter for ${email_address}"
        execute_mysql_query "${UPDATE_QUERY}"
    else
        # Insert new filter
        INSERT_QUERY="INSERT INTO sieve_filters
            (username, script_desc, script_name, script_data, filter_type, created, modified)
            VALUES
            ('${escaped_email}', '${escaped_description}', 'active', '${escaped_script}', 'prefilter', '${current_timestamp}', '${current_timestamp}');"
        
        log "Creating new filter for ${email_address}"
        execute_mysql_query "${INSERT_QUERY}"
    fi
    
    # Verify operation result
    if [ $? -eq 0 ]; then
        log "COMPLETED: Successfully processed ${email_address}"
    else
        log "ERROR: Failed to process filter for ${email_address}"
    fi
    
done < "${INPUT_FILE}"

log "Process completed successfully"
log "Detailed execution log available at: ${LOG_FILE}"
exit 0
