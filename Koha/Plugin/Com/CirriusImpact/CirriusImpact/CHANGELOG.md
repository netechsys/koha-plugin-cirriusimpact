## 1.2.3 - 2026-07-07

### HOLD CSV: wrong overdue messageText when Koha stores single-line YAML
- **FIXED:** Single-line `message_queue.content` (invalid YAML) no longer drops `sms.text` / `call.script`; content is normalized before `YAML::XS::Load`, with regex recovery and logging on failure.
- **FIXED:** Emergency SMS fallback is now **letter-code aware** (HOLD vs ODUE/DUE vs PREDUE, etc.); overdue wording is no longer applied to HOLD notices.
- **ADDED:** Phone (`call.script`) fallback when script is blank after parse; tries Koha `letter` table template before generated fallback text.

## 1.2.2 - 2026-06-12

### notification_mapping: DUE and DUEDGST
- **ADDED:** `DUE` and `DUEDGST` letter codes map to CirriusImpact notification type **1**, level **4**.
- **FIXED:** Overdue exports using letter code `DUE` no longer leave `notificationType` blank (CirriusImpact CSV validation rejection).

### PREDUE CSV: correct itemsID/title per notice row
- **FIXED**: Single PREDUE exports repeated the patron's earliest-due `itemsID` and `title` on every CSV row while `messageText` was correct per item (multi-item PREDUE class).
- **ENHANCED**: `_ci_backfill_predue_identifiers()` now extracts the title from rendered SMS/phone text (`due soon:`, `will be due soon:`, `is due`, etc.) and matches it to the patron's upcoming due items (same approach as CHECKOUT/ODUE).
- **ENHANCED**: Fallback uses `yaml_doc_index` when text extraction does not match.
- **FIXED**: `has_all` early exit now uses `next` per transport section instead of `return` from the whole backfill routine.

## 1.1.45 - 2026-05-26

### Notification Status Lifecycle + REST API
- **NEW**: Status now transitions through `pending` → `transmitted` → (`sent` | `pending` | `failed`).
  - When the plugin packages a notice into the outbound CSV and SFTPs it to the CirriusImpact service, the corresponding `message_queue` row is marked `transmitted` (was `sent`).
  - The remote CirriusImpact service is expected to call back into Koha to flip the status to `sent`, `pending`, or `failed` once the final delivery outcome is known.
- **NEW**: Extended `message_queue.status` ENUM to include `'transmitted'`. The plugin's `install` and `upgrade` hooks now run an idempotent `ALTER TABLE` that preserves existing ENUM values (no-op when `'transmitted'` is already present).
- **NEW**: REST API mounted at `/api/v1/contrib/cirriusimpact/`, modeled on ByWaterSolutions' MessageBee plugin:
  - `POST /message/{message_id}/status?status=sent|pending|failed[&failure_code=...][&subject=...][&content=...]`
  - `POST /message/{message_id}/content?content=...[&subject=...]`
  - Returns `204` on success, `400` on bad input, `404` when the message id is unknown, `500` on store errors.
- **NEW**: `Koha::Plugin::Com::CirriusImpact::API` controller and `openapi.json` shipped in the plugin bundle. The previously-empty `API.pm` stub is now a real Mojolicious controller; the duplicate stub at `Koha/Plugin/Com/CirriusImpact/CirriusImpact/API.pm` was removed.
- **ENHANCED**: Main plugin re-enables `api_routes()` and `api_namespace()` (namespace = `cirriusimpact`).

## 1.1.44 - 2026-05-26

### Expanded Notification Type Processing
- **FIXED**: `before_send_messages` previously only processed messages whose `letter_code` was an ODUE, HOLD, or PREDUE variant. Other notification types that already had installed message templates and notification mappings (CHECKOUT, CHECKIN, RENEWAL, AUTO_RENEWALS, AUTO_RENEWALS_DGST, MEMBERSHIP_EXPIRY, MEMBERSHIP_RENEWED, WELCOME, HOLD_SLIP) were silently dropped at the search filter and never reached the CirriusImpact pipeline.
- **ADDED**: New code-list helpers `_circulation_codes()` (CHECKOUT, CHECKIN), `_renewal_codes()` (RENEWAL, AUTO_RENEWALS, AUTO_RENEWALS_DGST), and `_membership_codes()` (MEMBERSHIP_EXPIRY, MEMBERSHIP_RENEWED, WELCOME).
- **ADDED**: `HOLD_SLIP` to `_hold_codes()` so hold-slip emails are picked up by the pipeline.
- **ENHANCED**: `before_send_messages` search filter now includes the new code groups in its `-or` clause so every type with an installed template flows through.
- **ENHANCED**: `_ci_backfill_additional_identifiers()` now backfills `HOLD_SLIP` (treated like HOLD), `AUTO_RENEWALS` (single item, like RENEWAL), and `AUTO_RENEWALS_DGST` (digest, multi-item with `title_list`/`itemsID_list`/`date_list`).

## 1.1.42 - 2026-02-18
- Describe the changes for 1.1.42 here.

## 1.1.41 - 2026-01-06
- Describe the changes for 1.1.41 here.

## 1.1.40 - 2026-01-06
- Describe the changes for 1.1.40 here.

## 1.1.39 - 2026-01-06
- Describe the changes for 1.1.39 here.

## 1.1.38 - 2025-11-12

### HOLDDGST Digest Title Deduplication and Message Text Fix
- **FIXED**: Titles were appearing duplicated in both the `title` field and `messageText` for HOLDDGST digest messages.
- **FIXED**: Item count was incorrect (showing 3 instead of 2) due to duplicate processing.
- **ENHANCED**: Improved digest grouping logic to properly extract titles from `title_list` with deduplication.
- **ENHANCED**: Single-message HOLDDGST cases now properly update `title` and `messageText` when multiple items are present.
- **ENHANCED**: Added proper handling of `itemsID_list` to ensure correct `itemsID` field in CSV.
- **DETAILS**: Refactored title/date extraction into a helper function that properly handles `title_list` arrays and dedupes entries.
- **TESTING**: Verified with SMS digest containing 2 holds that titles and messageText show correctly without duplication.

## 1.1.37 - 2025-11-11

### HOLDDGST Multi-Item Support
- **FIXED**: Voice digest (`HOLDDGST`) exports now include every waiting hold for the patron.
- **ENHANCED**: `itemsID`, `title`, and `date` columns list all items/dates using `; ` separators when more than one hold is present.
- **DETAILS**: Updated `_ci_backfill_additional_identifiers()` to fetch all waiting holds (removed `LIMIT 1`) and aggregate values for CSV output.
- **TESTING**: Verified with a patron having two waiting holds that both appear in the generated CSV.

## 1.1.25 - 2025-10-15

### Configurable Notification Type/Level Mapping System
- **NEW**: Added configurable YAML mapping file (`notification_mapping.yml`) for notification types and levels
- **NEW**: `_get_notification_type_and_level()` function with configurable mapping support
- **NEW**: Automatic CSV integration for `notificationType` and `notificationLevel` fields
- **NEW**: `kohaNotificationType` field (position 26) containing Koha letter codes
- **ENHANCED**: CSV field reordering to match exact specification:
  - `notificationType` (position 3): Mapping notification type (1-6)
  - `notificationLevel` (position 4): Mapping notification level (1-6)
  - `NotificationTypeID` (position 18): Empty field
  - `kohaNotificationType` (position 26): Koha letter code (HOLD, ODUE2, etc.)
- **FEATURES**: 
  - 21 supported message types with configurable Type/Level mapping
  - Fallback to hardcoded defaults if YAML file missing/corrupted
  - Cached loading for performance
  - No restart required for mapping changes
- **DOCUMENTATION**: Added `NOTIFICATION_TYPES.md` with complete usage guide
- **TESTING**: Verified configurable mapping system and CSV export integration

## 1.1.16 - 2025-10-14

### Critical Module Assignment Fix
- **FIXED**: HOLD templates now correctly assigned to 'reserves' module instead of 'circulation' module
- **ROOT CAUSE**: Phone messages were not being generated due to incorrect module assignments
- **SOLUTION**: Updated install_message_templates.pl to use correct module assignments:
  - HOLD* templates → 'reserves' module
  - ODUE* templates → 'circulation' module (unchanged)
  - PREDUE* templates → 'circulation' module (unchanged)
- **ADDED**: Missing HOLDPLACED and HOLDPLACED_PATRON templates
- **ENHANCED**: Direct database connection fallback for installer script
- **TESTED**: Verified phone messaging now works correctly for patron 51

### Template Coverage Improvements
- **ADDED**: HOLDPLACED_SMS and HOLDPLACED_PHONE templates
- **ADDED**: HOLDPLACED_PATRON_SMS and HOLDPLACED_PATRON_PHONE templates
- **ADDED**: HOLD_SLIP_EMAIL template in circulation module
- **COMPLETE**: All default Koha message types now have CirriusImpact templates

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
  - Phone: "Hello Terry. Centerville. You have 2 holds ready for pickup: Title 1; Title 2. Pickup by 10/20/2025. Call 555-0100."
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
- **Compatibility**: Works with US regional (555-0100) AND international (+44 20 1234 5678) formats
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
