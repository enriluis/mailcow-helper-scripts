# mailcow-helper-scripts
# Mailcow Sieve Filter Manager

## Why This Script?

Mailcow requires a different approach to email forwarding compared to Postfixadmin, especially when you need:

1. **Multi-recipient forwarding**
2. **Message modification during forwarding**
3. **Tracking of forwarded messages**

### Core Problem

In Mailcow:
- Aliases allow mail forwarding to multiple recipients
- But they **don't allow** message modification during forwarding
- The web UI doesn't provide message flagging options

### Implemented Solution

This script creates Sieve filters that:
1. **Forward** messages through aliases (`user_alias@domain.com`)
2. **Modify subjects** to identify forwarded messages (`[DEPARTMENT] Original subject`)
3. **Add importance flags** (High Priority)
4. **Automatically validate** that:
   - Mailbox exists
   - Corresponding alias is configured

### Key Benefits

1. **Consistency**: All forwarded messages are flagged consistently
2. **Visibility**: Easy identification in email clients
3. **Validation**: Script verifies all configurations are correct
4. **Automation**: Bulk processing via CSV

## Technical Documentation

### Workflow

1. The script verifies each account in the CSV:
   - Exists in the `mailbox` table
   - Has a corresponding alias (`[user]_alias@domain`)

2. For each valid account:
   - Creates/updates a Sieve filter that:
     - Forwards to the alias
     - Modifies the subject
     - Adds importance headers

3. Logs all operations in detail

### Comparison with Postfixadmin

| Feature                | Mailcow (this script)       | Postfixadmin          |
|------------------------|-----------------------------|-----------------------|
| Multi-recipient        | Requires alias + filter     | Direct configuration  |
| Message modification   | Yes (via Sieve)             | No                    |
| Auto-validation        | Yes                         | No                    |
| Priority/Importance    | Yes                         | No                    |

## Usage

1. Configure your CSV file with accounts to process
2. Run the script:
   ```bash
   ./sieve_filter_manager.sh
