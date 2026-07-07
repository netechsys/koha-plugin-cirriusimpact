# CirriusImpact Koha Plugin

Version: **1.1.41** (2026-01-10)

## Overview

This plugin integrates Koha ILS with CirriusImpact messaging services, forwarding patron notifications (holds, overdues, etc.) via multiple transport methods including SMS, Phone/Voice, Email, and WhatsApp.

**🌍 International Support:** The SMS::Send driver is an international-class driver that accepts phone numbers worldwide in any format - US (+1), UK (+44), Australia (+61), and other international formats, as well as regional/local formats. See `INTERNATIONAL_SUPPORT.md` for details.

## Key Features

### Latest Updates (v1.1.41)
- **Fixed Plugin Loading**: Resolved subroutine redefinition errors caused by duplicate nested plugin files
- **Automatic SMS Driver Discovery**: SMS drivers are automatically included in KPZ and discoverable via plugin @INC modification
- **OpenAPI Issues Resolved**: Removed problematic OpenAPI validation that caused hangs during SMSSendDriver configuration
- **KPZ Structure Improved**: Fixed KPZ packaging to exclude nested duplicate files
- **Improved Stability**: Plugin now loads and configures without errors or warnings

### CSV Export (v1.1.41)
- **Complete CSV Output**: Generates CSV files with all 25 required fields for CirriusImpact integration
- **Multi-Transport Support**: Handles SMS, Phone/Voice, Email, and WhatsApp messages
- **Smart ODUE Suppression**: Automatically suppresses phone messages when SMS exists for the same patron and ODUE notice
- **Accurate Title Resolution**: Shows correct book titles for different ODUE levels (ODUE, ODUE2, ODUE3)
- **Proper Field Mapping**: All fields correctly populated including phone numbers, patron details, item information, and dates

### Digest Grouping (v1.1.13)
- **HOLDDGST Digest Messages**: Automatically groups multiple individual HOLDDGST messages into single digest messages
- **Combined Titles**: Multiple item titles combined with semicolons (e.g., "Title 1; Title 2")
- **Updated Message Text**: Message content updated to show digest format (e.g., "You have 2 holds ready for pickup: Title 1; Title 2")
- **Patron Salutation**: STAB_userSaluation field populated based on patron gender (Mr./Ms.) when title field is empty
- **Transport-Specific Grouping**: Messages grouped by patron and transport type (SMS, Phone, Email)

### CSV Fields
The plugin exports the following fields in CSV format (messageText is optional based on configuration):
1. `commType` - Communication type (S=SMS, V=Voice/Phone, E=Email, W=WhatsApp)
2. `language` - Patron language preference
3. `notificationType` - Mapping notification type (1-6 from configurable mapping)
4. `notificationLevel` - Mapping notification level (1-6 from configurable mapping)
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
18. `NotificationTypeID` - Empty field
19. `ReportingOrgID` - Reporting organization ID
20. `PatronID` - Patron ID (borrowernumber)
21. `ItemRecordID` - Item record identifier
22. `RequestID` - Request identifier (message_id for holds)
23. `PickupAreaDescription` - Pickup location description
24. `TxnID` - Transaction ID
25. `AccountBalance` - Patron account balance
26. `kohaNotificationType` - Koha letter code (HOLD, ODUE2, CHECKOUT, etc.)
27. `messageText` - Full message content (SMS text, Phone script, Email body) - **Optional, configurable**

### Configuration Options
- **SFTP Settings**: Host, username, password for file upload
- **Archive Directory**: Local directory for CSV file storage
- **Transport Toggles**: Enable/disable Phone, SMS, Email, WhatsApp
- **ODUE Suppression**: Skip calling ODUE if patron has SMS or Email
- **MessageText Column**: Enable/disable inclusion of messageText column in CSV output
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

1. Download the latest `koha-plugin-cirriusimpact-v{VERSION}.kpz` file from the [GitHub releases page](https://github.com/netechsys/koha-plugin-cirriusimpact/releases)
2. In Koha, go to **Tools → Plugins → Upload Plugin**
3. Upload the `.kpz` file
4. The plugin automatically installs, including the SMS::Send drivers. **No manual SMS driver installation required!**
   
   The SMS drivers (`SMS::Send::CirriusImpact` and `SMS::Send::US::CirriusImpact`) are:
   - Automatically included in the KPZ package
   - Automatically extracted to `/var/lib/koha/{instance}/plugins/SMS/Send/` during installation
   - Automatically discoverable via the plugin's @INC modification (no manual configuration needed)

5. Install message templates (optional but recommended):
   ```bash
   cd /var/lib/koha/INSTANCE/plugins/Koha/Plugin/Com/CirriusImpact/CirriusImpact/
   sudo perl install_message_templates.pl
   ```
6. Configure Koha's SMS driver: **Administration → System Preferences → Patrons → SMSSendDriver** = `US::CirriusImpact`
7. Configure the plugin:
   - Go to **Tools → Plugins → CirriusImpact → Configure**
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

## Troubleshooting

### Plugin Not Loading
If you encounter "Subroutine redefined" errors, ensure you've installed the latest KPZ version (1.1.41+). Older versions may have had nested duplicate files that caused this issue.

### SMS Drivers Not Found
The SMS drivers are automatically extracted during KPZ installation. They should be discoverable at:
- `/var/lib/koha/{instance}/plugins/SMS/Send/CirriusImpact.pm`
- `/var/lib/koha/{instance}/plugins/SMS/Send/US/CirriusImpact.pm`

The plugin's BEGIN block automatically adds the plugins directory to Perl's @INC path, making these drivers discoverable without manual configuration. If drivers are not found:
1. Verify the plugin KPZ was installed successfully
2. Check that the files exist in `SMS/Send/` directory
3. Reinstall the plugin KPZ if files are missing
4. Restart Koha Plack: `sudo koha-plack --restart {instance}`

### SMSSendDriver Configuration Hanging
Version 1.1.41+ resolves this issue. If you experience hangs, ensure you're running the latest version and restart Koha Plack:
```bash
sudo koha-plack --restart {instance}
```

## Version History

See [CHANGELOG.md](CHANGELOG.md) for detailed version history.

### Recent Versions

**Version 1.1.41** (2026-01-10)
- Fixed plugin loading issues (removed duplicate nested file causing subroutine redefinitions)
- SMS drivers automatically discoverable via plugin @INC modification
- Removed problematic OpenAPI validation that caused hangs during SMSSendDriver configuration
- KPZ structure corrected to exclude nested plugin file
- Updated plugin paths from ByWaterSolutions to CirriusImpact
- Plugin now loads correctly without errors

**Version 1.1.25** (2025-10-15)
- CSV export with all 25 required fields
- Multi-transport support (SMS, Phone, Email, WhatsApp)
- Smart ODUE suppression
- Accurate title resolution

**Version 1.1.13** (2025-10-01)
- HOLDDGST digest message grouping
- Combined titles with semicolons
- Transport-specific grouping

## Contributing

This plugin is maintained by CI Management Services. For issues, feature requests, or contributions, please visit the [GitHub repository](https://github.com/netechsys/koha-plugin-cirriusimpact).
