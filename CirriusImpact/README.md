# CirriusImpact Koha Plugin

Version: **1.1.9** (2025-10-12)

## Overview

This plugin integrates Koha ILS with CirriusImpact messaging services, forwarding patron notifications (holds, overdues, etc.) via multiple transport methods including SMS, Phone/Voice, Email, and WhatsApp.

**🌍 International Support:** The SMS::Send driver is an international-class driver that accepts phone numbers worldwide in any format - US (+1), UK (+44), Australia (+61), and other international formats, as well as regional/local formats. See `INTERNATIONAL_SUPPORT.md` for details.

## Key Features

### CSV Export (v1.1.5)
- **Complete CSV Output**: Generates CSV files with all 25 required fields for CirriusImpact integration
- **Multi-Transport Support**: Handles SMS, Phone/Voice, Email, and WhatsApp messages
- **Smart ODUE Suppression**: Automatically suppresses phone messages when SMS exists for the same patron and ODUE notice
- **Accurate Title Resolution**: Shows correct book titles for different ODUE levels (ODUE, ODUE2, ODUE3)
- **Proper Field Mapping**: All fields correctly populated including phone numbers, patron details, item information, and dates

### CSV Fields
The plugin exports the following 25 fields in CSV format:
1. `commType` - Communication type (S=SMS, V=Voice/Phone, E=Email, W=WhatsApp)
2. `language` - Patron language preference
3. `notificationType` - Letter code (HOLD, ODUE, ODUE2, ODUE3, etc.)
4. `notificationLevel` - Notification level
5. `patronBarCode` - Patron barcode
6. `STAB_userSalutation` - Patron salutation (Mr, Ms, etc.)
7. `patronFirstName` - Patron first name
8. `patronLastName` - Patron last name
9. `phone` - Phone number for contact
10. `email` - Email address
11. `branch` - Branch code
12. `branchname` - Branch name
13. `itemsID` - Item ID
14. `date` - Due date or notification date
15. `title` - Item title
16. `DeliveryOptionID` - Delivery option identifier
17. `LanguageID` - Language identifier
18. `NotificationTypeID` - Notification type identifier
19. `ReportingOrgID` - Reporting organization ID
20. `PatronID` - Patron ID (borrowernumber)
21. `ItemRecordID` - Item record identifier
22. `RequestID` - Request identifier (message_id for holds)
23. `PickupAreaDescription` - Pickup location description
24. `TxnID` - Transaction ID
25. `AccountBalance` - Patron account balance

### Configuration Options
- **SFTP Settings**: Host, username, password for file upload
- **Archive Directory**: Local directory for CSV file storage
- **Transport Toggles**: Enable/disable Phone, SMS, Email, WhatsApp
- **ODUE Suppression**: Skip calling ODUE if patron has SMS or Email
- **Section Order**: Configurable output section ordering

### Message Processing
- **Template Rendering**: Supports `[% var %]` and `{{ var }}` placeholders in YAML notice templates
- **Nested Structure Support**: Handles nested `sms:` / `call:` maps and flat keys
- **Direct Database Queries**: Uses optimized SQL queries for reliable overdue item data retrieval
- **Print Transport Handling**: Automatically skips print transport messages in CSV output

### Debug & Logging
- Comprehensive debug output for troubleshooting
- Detailed logging of message processing for all transport types
- Clean error handling with informative messages

## Installation

1. Download the latest `CirriusImpact.kpz` file
2. In Koha, go to Tools → Plugins → Upload Plugin
3. Upload the `.kpz` file
4. Extract and install the SMS driver:
   ```bash
   cd /var/lib/koha/INSTANCE/plugins/Koha/Plugin/Com/ByWaterSolutions/CirriusImpact/
   sudo perl install_sms_driver.pl
   ```
5. Configure Koha's SMS driver: Administration → System Preferences → Patrons → SMSSendDriver = `US::CirriusImpact`
6. Configure the plugin:
   - Go to Tools → Plugins → CirriusImpact → Configure
   - Enter SFTP credentials (host, username, password)
   - Set archive directory (defaults to `/var/lib/koha/{instance}/CirriusImpact_archive`)
   - Enable desired transport methods (SMS, Phone, Email, WhatsApp)

**Quick Start:** See `QUICKSTART.md` for 5-minute setup  
**Detailed Guide:** See `INSTALL.md` for complete instructions

## Usage

The plugin automatically processes messages from Koha's message queue:
1. Run `/usr/share/koha/bin/cronjobs/overdue_notices.pl` to generate overdue notices
2. Run `/usr/share/koha/bin/cronjobs/process_message_queue.pl` to process the queue
3. Plugin generates CSV file and uploads to configured SFTP server
4. CSV file also archived locally for reference

**Note**: You may see a warning message `SMS::Send driver CirriusImpact does not exist, or is not installed` when running `process_message_queue.pl`. This is expected and can be safely ignored - it's Koha's fallback SMS mechanism attempting to load the driver, but the plugin uses the `before_send_messages` hook instead, which runs before this fallback is triggered.

## Version History

See [CHANGELOG.md](CHANGELOG.md) for detailed version history.

## Previous Versions

Version: **1.1.4** (2025-09-20)
- Nested `sms:` / `call:` maps and flat keys supported
- `sms.reference`, `sms.text`, `call.reference`, `call.script` rendered or preserved literally if unresolved
- Section-order control
- Config page: copyable YAML samples (safe rendered)
- Ensures `sms` and `call` sections appear in JSON when the feature is enabled
- Four safe-rendered samples (Hold SMS/Phone, Overdue SMS/Phone) with **Copy** buttons
- Placeholder renderer supports `[% var %]` and `{{ var }}` in YAML fields
- JSON section order configurable via plugin configuration
