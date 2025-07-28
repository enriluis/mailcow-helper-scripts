# Mailcow Alias Bulk Importer

A script to **bulk import/update email aliases** in Mailcow via its API, with checks for existing aliases and conditional updates.

## Purpose
This script automates the migration or synchronization of email aliases from PostfixAdmin to Mailcow. It:
- Processes a JSON file containing alias data.
- **Checks if each alias exists** in Mailcow before creating/updating.
- **Updates existing aliases** if their `goto` (destination) field changes.
- Logs operations with timestamps for auditing.
- Provides summary statistics (success/failure counts).

---

## Key Design Notes
### Why `_alias@` Prefix?
The script transforms addresses like `user@domain.com` into `user_alias@domain.com` because:
1. **Sieve Filter Compatibility**:  
   Mailcow’s Sieve filters cannot directly distinguish between aliases and primary addresses in routing rules. By adding `_alias` to the local part:
   - Sieve scripts can easily **identify alias traffic** (e.g., `if address :matches "*_alias@*" { ... }`).
   - Enables separate filtering logic for aliases vs. primary emails.
   
2. **Mailcow Limitation Workaround**:  
   Mailcow treats aliases and primary addresses as equals in routing. The prefix ensures aliases are explicitly tagged for later processing.

---

## Workflow
1. **Input**: A JSON file (one alias per line) generated from PostfixAdmin.
2. **Validation**: Checks for required tools (`jq`, `curl`) and valid JSON.
3. **API Interaction**:
   - Queries Mailcow’s API to check for existing aliases.
   - Creates new aliases or updates existing ones (if `goto` differs).
4. **Output**: Logs results to `output.log` and prints a summary.

---

## Requirements
1. **Tools**:
   - `jq`: For JSON processing.
   - `curl`: For Mailcow API requests.
2. **PostfixAdmin Data Export**:
   - Run this SQL query in PostfixAdmin to extract aliases where `address != goto` (custom aliases only):
     ```sql
     SELECT 
       CONCAT(
         '{',
         '"active": "1", ',
         '"address": "', 
           CONCAT(
             SUBSTRING_INDEX(address, '@', 1),  -- Extract local part
             '_alias@',                         -- Add prefix for Sieve
             SUBSTRING_INDEX(address, '@', -1)  -- Extract domain
           ), 
         '", ',
         '"goto": "', goto, '"',
         '}'
       ) AS json_data
     FROM 
       postfix.alias
     WHERE 
       address != goto;
     ```
   - Save the output as `input_file.json` (one JSON object per line).

3. **Mailcow API Credentials**:
   - Set `MAILCOW_API_KEY` and `MAILCOW_API_URL` in the script or environment.

---

## Usage
1. **Run the script**:
   ```bash
   ./import_aliases.sh input_file.json
##   Notes
Why address != goto?: The SQL query filters only custom aliases (e.g., support@domain.com → team@domain.com), ignoring catch-alls (user@domain.com → user@domain.com).
Logs: Detailed logs are saved in output.log.
Safety: The script avoids duplicate API calls by checking existing aliases first.
For support, contact enriluis@gmail.com.