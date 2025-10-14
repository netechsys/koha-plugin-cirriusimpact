## 1.1.15 - 2025-10-13

### Message Template Installer
- **NEW**: Added `install_message_templates.pl` script for automatic template installation
- **30+ Templates**: Installs pre-configured templates for all supported message types
- **Complete Coverage**: Includes HOLD, CHECKOUT, CHECKIN, ODUE, PREDUE, and membership templates
- **SMS & Phone**: All templates include both SMS and Phone transport versions
- **CirriusImpact Ready**: All templates include proper YAML markers and CirriusImpact integration
- **Easy Installation**: Single command installs all templates: `sudo perl install_message_templates.pl`
- **Update Support**: Script updates existing templates or installs new ones as needed

### MessageText Configuration Option
- **NEW**: Added configuration checkbox to enable/disable messageText column in CSV output
- **Flexible Output**: Users can choose whether to include full message content in CSV files
- **Configuration UI**: Added "Include messageText column in CSV output" checkbox in plugin configuration
- **Conditional Processing**: CSV generation now checks configuration before including messageText column
- **Backward Compatible**: Default behavior maintains current functionality

## 1.1.14 - 2025-10-13

### Documentation Updates
- **NEW**: Updated README.md with digest grouping feature description
- **NEW**: Added comprehensive HOLDDGST digest grouping examples to QUICKSTART.md
- **NEW**: Added detailed digest grouping section to NOTICE_EXAMPLES.md
- **Enhanced**: Updated table of contents and cross-references
- **Complete**: All documentation now reflects current functionality including STAB_userSaluation population

## 1.1.13 - 2025-10-13

### HOLDDGST Digest Grouping
- **NEW**: Automatic grouping of multiple individual HOLDDGST messages into single digest messages
- **Smart Grouping**: Messages grouped by patron ID and transport type (SMS, Phone, Email)
- **Combined Titles**: Multiple item titles combined with semicolons (e.g., "The poems; Learning SQL")
- **Updated Message Text**: Message content automatically updated to show digest format
  - SMS: "CPL: You have 2 holds ready for pickup: Title 1; Title 2. Pickup by 10/20/2025."
  - Phone: "Hello Terry. Centerville. You have 2 holds ready for pickup: Title 1; Title 2. Pickup by 10/20/2025. Call 7315551234."
- **Patron Salutation**: STAB_userSaluation field populated based on patron gender (Mr./Ms.) when title field is empty
- **Implementation**: Digest grouping logic in `_generate_csv_output()` function with comprehensive logging

### Account and Hold Message Support
- **NEW**: Added backfill support for 7 additional message types: ACCOUNT_CREDIT, ACCOUNT_DEBIT, ACCOUNT_PAYMENT, ACCOUNT_WRITEOFF, ACCOUNTS_SUMMARY, HOLDPLACED, HOLDPLACED_PATRON
- **Database Integration**: Enhanced `_ci_backfill_additional_identifiers()` to query accountlines and reserves tables
- **Account Messages**: Queries `accountlines` table for transaction data, amounts, descriptions, and balances
- **Hold Messages**: Queries `reserves` table for hold placement information and expiration dates
- **Automatic Population**: All new message types automatically populate `itemsID`, `biblionumber`, `title`, and `date` fields
- **Coverage**: Backfill applies to all transport types (SMS, Phone, Email, WhatsApp)

### Template Examples Added
- **Documentation**: Added comprehensive templates for all 7 new message types in QUICKSTART.md and NOTICE_EXAMPLES.md
- **Phone Support**: Added phone templates for all new message types with proper greeting and call-to-action
- **Copy-Paste Ready**: All templates include proper YAML markers and variable usage
- **Expected Output**: Added detailed examples showing exactly what messages will look like
- **Template Variables**: Added support for account-specific variables (amount, description, balance, transaction_count)

### Implementation Details
- **Location**: Enhanced function at line 2075 in `CirriusImpact.pm`
- **Integration**: Called after each transport section is created (lines 498, 561, 664, 709, 746)
- **SQL Queries**: 
  - Account: `SELECT al.accountlines_id, al.amount, al.description FROM accountlines al...`
  - Summary: `SELECT SUM(al.amountoutstanding), COUNT(al.accountlines_id) FROM accountlines al...`
  - Hold: `SELECT r.reserve_id, r.biblionumber, b.title FROM reserves r JOIN biblio b...`
- **Error Handling**: Robust error handling and logging for all new message types
- **Debug Logging**: Comprehensive logging for troubleshooting

### Complete Message Type Coverage
- **Total Support**: Plugin now supports 20 different message types
- **Core Circulation**: HOLD, CHECKOUT, CHECKIN, ODUE, PREDUE (with digest variants)
- **Additional Types**: HOLD_CHANGED, HOLD_REMINDER, MEMBERSHIP_EXPIRY, MEMBERSHIP_RENEWED, RENEWAL, WELCOME
- **Account & Hold**: ACCOUNT_CREDIT, ACCOUNT_DEBIT, ACCOUNT_PAYMENT, ACCOUNT_WRITEOFF, ACCOUNTS_SUMMARY, HOLDPLACED, HOLDPLACED_PATRON
- **Production Ready**: All message types have automatic data population and comprehensive documentation

## 1.1.12 - 2025-10-13

### PREDUE Message Support
- **NEW**: Added `_ci_backfill_predue_identifiers()` function for PREDUE and PREDUEDGST notices
- **FIXED**: PREDUE messages now populate `itemsID`, `biblionumber`, `title`, and `date` fields
- **Query**: Uses direct SQL to fetch upcoming due items from `issues` table
- **Digest Support**: Handles both single PREDUE and digest PREDUEDGST message types
- **Message Correction**: Automatically fixes empty template variables in message text
- **Multi-Item Display**: For digest messages, shows all items in message text even if CSV shows first item
- **Coverage**: Backfill applies to all transport types (SMS, Phone, Email, WhatsApp)

### Template Examples Added
- **Documentation**: Added complete PREDUE templates to QUICKSTART.md and NOTICE_EXAMPLES.md
- **Copy-Paste Ready**: All templates include proper YAML markers and variable usage
- **Digest Logic**: Templates handle both single items and multiple items with proper conditional logic
- **Fallback Support**: Simple templates work even when Koha template variables are empty

### Implementation Details
- **Location**: New function at line 1912 in `CirriusImpact.pm`
- **Integration**: Called after each transport section is created (lines 497, 559, 661, 705, 741)
- **SQL Query**: `SELECT i.itemnumber, it.biblionumber, b.title, i.date_due FROM issues i...`
- **Message Text Fix**: Regex replacement for empty variables in digest messages
- **Debug Logging**: Comprehensive logging for troubleshooting

### Testing Status
- ✅ PREDUE messages: Working perfectly with automatic backfill
- ✅ PREDUEDGST messages: Working perfectly with all items in message text
- ✅ CSV fields: All populated correctly (itemsID, title, date, biblionumber)
- ✅ Message text: Automatically corrected to show all items for digest messages

## 1.1.9 - 2025-10-12

### CHECKIN Message Support
- **NEW**: Added `_ci_backfill_checkin_identifiers()` function for CHECKIN notices
- **FIXED**: CHECKIN messages now populate `itemsID`, `biblionumber`, `title`, and `date` (returndate)
- **Query**: Uses direct SQL to fetch recent check-in data from `old_issues` table (last 24 hours)
- **Title Matching**: Extracts title from rendered script/text and matches to database check-in
- **Fallback**: Uses `yaml_doc_index` for item distribution when title matching fails
- **Coverage**: Backfill applies to all transport types (SMS, Phone, Email, WhatsApp)

### ODUE Template Simplification
- **FIXED**: ODUE templates simplified to avoid `overdues.size` method calls
- **Workaround**: Addresses Koha Template Toolkit issue with `.size` on Koha::Objects collections
- **Format**: Single-item format (one message per overdue item)
- **Documentation**: Updated QUICKSTART.md and NOTICE_EXAMPLES.md with working templates
- **Behavior**: ODUE generates individual messages per overdue item (not digest)
- **Suppression**: Phone ODUE messages correctly suppressed when patron has SMS enabled

### Implementation Details
- **Location**: New function at line 1472 in `CirriusImpact.pm`
- **Integration**: Called after each transport section is created (lines 496, 557, 658, 701, 736)
- **Title Extraction**: Regex pattern `/checked in:\s+(.+?)\.\s+Thank you/i`
- **Data Source**: `old_issues` table (WHERE `returndate >= DATE_SUB(NOW(), INTERVAL 1 DAY)`)

### Testing Status
- ✅ HOLD messages: Working perfectly
- ✅ CHECKOUT messages: Working perfectly
- ✅ CHECKIN messages: Working perfectly
- ✅ ODUE messages: Working perfectly (simplified format)
- ✅ ODUE suppression: Phone messages correctly suppressed when SMS enabled

## 1.1.8 - 2025-10-12

### Critical Bug Fixes (Multi-Document YAML Support)
- **FIXED**: Koha's invalid YAML separator `------` now converted to valid `---` before parsing
- **FIXED**: Multi-document YAML from concatenated notices now parses correctly
- **FIXED**: Phone CHECKOUT messages now populate all fields (itemsID, title, date, messageText)
- **FIXED**: Title matching extracts title from script and matches to correct checkout in database
- **Enhancement**: Each YAML document tracked separately with `yaml_doc_index` for accurate item distribution
- **Enhancement**: Intelligent title extraction and matching prevents misaligned CSV columns

### CSV Export Improvements
- **FIXED**: messageText column now populated correctly for phone messages (call:script content)
- **FIXED**: itemsID, title, and messageText columns now perfectly aligned for all CHECKOUT messages
- **Enhancement**: Title extracted from rendered template script and matched to database checkout
- **Reliability**: All CSV columns consistent across multiple checkout messages

### Testing Results
- ✅ HOLD messages: Working perfectly (4 holds tested)
- ✅ CHECKOUT messages: Working perfectly (3 checkouts tested)
- ✅ CSV columns aligned: itemsID, title, messageText all match
- ✅ Multi-document YAML: Properly parsed and processed
- ✅ Phone scripts: Correctly populated in messageText column

## 1.1.7 - 2025-10-11

### SMS::Send Driver Integration
- **NEW**: Created SMS::Send::US::CirriusImpact driver for Koha integration
- **Driver Location**: `/usr/share/perl5/SMS/Send/US/CirriusImpact.pm`
- **Regional Support**: Accepts phone numbers with or without + prefix (US regional and international)
- **Installation Scripts**: Added automated `install_sms_driver.pl` and `update_and_test.sh`
- **Verification**: Added `verify_installation.pl` to check complete installation

### Critical Bug Fixes
- **FIXED**: $self object interpolation bug causing `HASH(0x...)` to appear in text fields
- **FIXED**: `_ci_insert_title_into_text()` now handles both method and function call styles
- **FIXED**: Phone messages not getting backfilled with item data
- **FIXED**: Regional phone number validation error

### CHECKOUT Message Enhancements
- **NEW**: `_ci_backfill_checkout_identifiers()` function
- **Enhancement**: CHECKOUT messages now populate itemsID, biblionumber, title, and date automatically
- **Query**: Uses direct SQL to fetch active checkout data from issues table
- **Distribution**: Uses message_id to distribute titles across multiple checkouts

### Backfill Improvements
- **Enhancement**: Both `_ci_backfill_odue_identifiers()` and `_ci_backfill_checkout_identifiers()` now check ALL transport sections (call, sms, email, whatsapp)
- **Fix**: Backfill now runs AFTER each transport section is created (lines 633, 675, 709)
- **Reliability**: No longer relies on database transport type, checks actual section existence
- **Coverage**: Works for phone/voice, SMS, email, and WhatsApp messages

### Documentation
- **NEW**: NOTICE_EXAMPLES.md - 30+ complete notice template examples
- **NEW**: DIGEST_QUICK_REFERENCE.md - Quick reference for digest notices
- **NEW**: TESTING.md - Comprehensive testing guide
- **NEW**: INTERNATIONAL_SUPPORT.md - International phone number documentation
- **NEW**: FIXES_APPLIED.md - Complete list of all fixes
- **NEW**: INSTALL.md - Detailed installation guide
- **NEW**: QUICKSTART.md - 5-minute setup guide
- **Updated**: All documentation to use `US::CirriusImpact` driver

### Notice Template Examples
- **10 CHECKOUT digest options**: Single item, all items, formatted lists, numbered, multi-transport
- **10 HOLD digest options**: With expirations, pickup locations, compact formats
- **10 ODUE digest options**: With fine amounts, days overdue, severity grouping, escalating urgency
- **Syntax Guide**: Complete Template Toolkit reference for loops and variables

### Testing & Verification
- **NEW**: Automated update and test script (`update_and_test.sh`)
- **NEW**: Complete testing procedures (TESTING.md)
- **NEW**: Final test instructions (TEST_NOW.txt)
- **Enhancement**: Color-coded output for all scripts (✓ success, ✗ error, ⚠ warning, ℹ info)

### Driver Changes
- **Change**: Moved from `SMS::Send::CirriusImpact` to `SMS::Send::US::CirriusImpact`
- **Reason**: US regional driver allows phone numbers without + prefix while still accepting international numbers
- **Compatibility**: Works with US regional (7315551234) AND international (+44 20 1234 5678) formats
- **Version**: Driver v1.0.1

### Configuration
- **Update Required**: SMSSendDriver preference must be set to 'US::CirriusImpact' (changed from 'CirriusImpact')
- **Documentation**: All guides updated with correct driver name

### Package Contents
- **Total Files**: 22 (increased from 11)
- **Documentation**: 9 markdown files (75KB)
- **Scripts**: 3 executable scripts (install, verify, update)
- **Examples**: 30+ notice templates
- **Package Size**: ~150KB total

### Known Issues
- **SMTP Error**: Non-CirriusImpact email messages may show SMTP connection error (Koha configuration issue, not plugin bug)
- **Workaround**: Configure SMTP with `koha-email-enable` or ensure all email notices have `CirriusImpact: yes` header

---

## 1.1.6 - 2025-10-11
- **Installation Fix**: Archive directory is now automatically created on first run if it doesn't exist
- **Error Handling**: Fixed "Can't open log file (No such file or directory)" error on fresh installations
- **Directory Creation**: Archive directory is created with proper permissions (0755) before Log4perl initialization

## 1.1.5 - 2025-10-11
- **MAJOR UPDATE**: Complete CSV output implementation with all 25 required fields
- **CSV Format**: Changed output format from JSON to CSV for CirriusImpact integration
- **Multi-Transport Support**: Full support for SMS, Phone/Voice, Email, and WhatsApp message types
- **ODUE Suppression**: Implemented cross-message suppression - phone messages are automatically suppressed when SMS exists for the same patron and ODUE notice
- **Title Resolution**: Fixed title field to show correct book titles for different ODUE messages (ODUE, ODUE2, ODUE3)
- **Phone Number Handling**: Fixed phone number population for all transport types (phone, SMS)
- **Letter Code Display**: Changed `notificationType` field to display letter codes (HOLD, ODUE, ODUE2, ODUE3) instead of transport types
- **Print Transport Handling**: Added logic to skip print transport messages in CSV output
- **Database Queries**: Implemented direct SQL queries for overdue items to ensure reliable data retrieval
- **Data Structure Fixes**: Corrected data extraction to properly navigate message_type structures
- **Debug Output**: Added comprehensive logging for troubleshooting (phone, email, SMS, WhatsApp sections)
- **Configuration**: Fixed configuration mapping for `skip_odue_if_other_if_sms_or_email` setting
- **Error Handling**: Fixed uninitialized value warnings in debug output
- **CSV Fields**: All 25 fields properly populated: commType, language, notificationType, notificationLevel, patronBarCode, STAB_userSalutation, patronFirstName, patronLastName, phone, email, branch, branchname, itemsID, date, title, DeliveryOptionID, LanguageID, NotificationTypeID, ReportingOrgID, PatronID, ItemRecordID, RequestID, PickupAreaDescription, TxnID, AccountBalance

## 1.1.4
- Fix: declare SMS/WhatsApp variables under strict; WhatsApp exports as its own section; add `whatsapp` to default section order; clean $VERSION.
- Added YAML sample for Email notice (commType E).
- Added YAML sample for WhatsApp notice (treated as SMS with commType W).
- Remove JSON example from configuration page.
- Replace with updated YAML samples for Phone (call) and SMS showing all available fields (no copy buttons).
- Place the additional mapping fields directly inside the active transport section (`call` for phone, `sms` for SMS) so they appear in the output without changing `section_order`.
- Keep blanks for missing values. `commType` = V (phone), E (email), S (sms).
- Add `export_fields` block to JSON export including requested static mappings.
- Map commType to V/E/S based on transport (phone/email/sms).
- FIX: honor nested `sms:`/`call:` keys (`text`, `reference`, `to_numbers`) and flat keys.
- Preserve unresolved TT tokens literally.
- Keep `sms`/`call` sections when enabled/transport/hints exist.
- Add `sms`/`call` sections unconditionally based on enable/transport/YAML hints.
- Add Copy buttons to configuration samples.
- Safe HTML-escaped TT placeholders in sample YAML (avoids 500 errors).
- Fix Error 500 by HTML-escaping TT placeholders in sample YAMLs.
- Add Overdue (SMS/Phone) samples to configuration.
- Keep Enable Phone/SMS toggles and section-order control.
