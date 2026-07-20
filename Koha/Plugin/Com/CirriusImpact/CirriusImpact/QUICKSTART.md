# CirriusImpact Plugin - Quick Start Guide

## Overview

**International Support:** This plugin works with phone numbers in any format - US (+1), UK (+44), Australia (+61), or regional formats. The SMS::Send driver accepts international and local number formats.

Download Latest Released version of Plugin from the GIT Repository.

## Installation (10 minutes)

### Step 1: Upload Plugin to Koha from the Administration Website.

1. Download the latest `koha-plugin-cirriusimpact-v{VERSION}.kpz` file from the [GitHub releases page](https://github.com/netechsys/koha-plugin-cirriusimpact/releases)
2. Go to **More > Administration > Plugins > Upload Plugin**
3. Select the downloaded KPZ file (e.g., `CirriusImpact-1.1.41.kpz`)
4. Click **Upload**
5. Wait for upload and installation to complete

**Note:** The SMS::Send drivers are **automatically included** in the KPZ and extracted during installation. They are automatically discoverable via the plugin's @INC modification - **no manual installation required!**

The drivers are automatically extracted to:
- `/var/lib/koha/{instance}/plugins/SMS/Send/CirriusImpact.pm` (international)
- `/var/lib/koha/{instance}/plugins/SMS/Send/US/CirriusImpact.pm` (regional + international)

### Step 2: Configure Koha System Preference

Set the SMS driver in Koha:

**More > Administration**

- Enter SMS in System preferences and select Search.

- Enter value for **SMSSendDriver**: and select Save all Patrons Preferences.

**Recommended:** 
- **SMSSendDriver**: `US::CirriusImpact`  
  *(Accepts both regional and international phone numbers)*

**Alternative (international only):**
- **SMSSendDriver**: `CirriusImpact`  
  *(Requires + prefix on all phone numbers)*

### Step 3: Verify Installation

Run the verification script in the SSH session:

```bash
cd /var/lib/koha/INSTANCE/plugins/Koha/Plugin/Com/CirriusImpact/CirriusImpact/
sudo koha-shell INSTANCE (where INSTANCE is the library instance name.)
perl verify_installation.pl
```

**Expected output:**
```
✓ SMS::Send::US::CirriusImpact driver is installed (current)
✓ SMS::Send::CirriusImpact driver is installed (legacy)
✓ All required Perl modules found
✓ All plugin files present
✓ All checks passed!
```

**Note:** The SMS drivers are automatically extracted during KPZ installation. The verification script confirms they are discoverable at `/var/lib/koha/{instance}/plugins/SMS/Send/`.

**Common warnings (normal):**
- ⚠ Archive directory not found → **Will be created automatically on first run**

### Step 4: Configure Plugin

1. Go to **More > Administration > Plugins**
2. Find **CirriusImpact** → **Actions** → **Configure**
3. Enter your settings:
   - **SFTP Host**: (provided by CirriusImpact)
   - **SFTP Username**: (provided by CirriusImpact)
   - **SFTP Password**: (provided by CirriusImpact)
   - **Archive Directory**: `/var/lib/koha/INSTANCE/CirriusImpact_archive`
   
   ** Based on Solution provided, select accordinly below **
   - **Enable SMS**: ☑
   - **Enable Phone**: ☑
   - **Enable Email**: ☑
   - **Enable WhatsApp**: ☑
   - **Enable Skip calling ODUE if patron has SMS or Email**: ☑  (This will make the system only send the message in SMS of Email if the patron has that notification preference selected.  If this is not checked, and the patron has SMS or Email notification preferences configured, the system will send both SMS/Email and Phone notices.)
   - **Include messageText column in CSV output**: ☑  (This will include the full message content in the CSV file. Uncheck to exclude messageText column for smaller CSV files.)
4. Click **Save**

### Step 5: Install Message Templates (Optional but Recommended)

Install pre-configured CirriusImpact notice templates from SSH. Run as the Koha instance user:

```bash
sudo koha-shell INSTANCE -c \
  'perl /var/lib/koha/INSTANCE/plugins/Koha/Plugin/Com/CirriusImpact/CirriusImpact/install_message_templates.pl --no-restart'
```

**Default behavior** (no extra flags):
- **Services:** SMS and phone (`message_transport_type` = `sms` and `phone`)
- **Languages:** `default`, `en`, `es-ES`, `fr-CA` (English, Spanish, French)
- **Default tab:** Koha `letter.lang=default` is filled from English (`en`)

Templates cover HOLD, HOLDDGST, CHECKOUT, CHECKIN, ODUE/ODUE2/ODUE3, PREDUE/PREDUEDGST, HOLD_CHANGED, HOLD_REMINDER, RENEWAL, MEMBERSHIP_EXPIRY, MEMBERSHIP_RENEWED, WELCOME, and more. All include CirriusImpact YAML markers and GSM-7-safe SMS text.

#### Common install variations

**SMS only** (no phone/voice templates):

```bash
sudo koha-shell INSTANCE -c \
  'perl .../install_message_templates.pl --services=sms --no-restart'
```

**Phone/voice only:**

```bash
sudo koha-shell INSTANCE -c \
  'perl .../install_message_templates.pl --services=phone --no-restart'
```

**Spanish-primary library** (Default tab = Spanish; still installs `en`, `es-ES`, `fr-CA`):

```bash
sudo koha-shell INSTANCE -c \
  'perl .../install_message_templates.pl --default-language=spa --no-restart'
```

**SMS only, Spanish default:**

```bash
sudo koha-shell INSTANCE -c \
  'perl .../install_message_templates.pl --services=sms --default-language=spa --no-restart'
```

**Limit languages** (example: English and Spanish only):

```bash
sudo koha-shell INSTANCE -c \
  'perl .../install_message_templates.pl --languages=default,en,es-ES --no-restart'
```

#### Options reference

| Option | Values | Default |
|--------|--------|---------|
| `--services` | `sms`, `phone` (comma-separated) | `sms,phone` |
| `--default-language` | `en`/`eng`, `es-ES`/`spa`, `fr-CA`/`fre` | `en` |
| `--languages` | `default`, `en`, `es-ES`, `fr-CA` (comma-separated) | all four |
| `--no-restart` | skip interactive Koha restart prompt | off |

Aliases: `--transports` = `--services`; `text`→sms; `voice`/`call`→phone.

For multilingual notices, enable **TranslateNotices** and add `en` / `es-ES` / `fr-CA` to **OPACLanguages**. See `TEMPLATE_I18N.md` for language and SMS character details.

### Step 6: Configure Notice Templates (If Not Using Auto-Install)

**Important:** SMS, Phone, Email, and WhatsApp are **separate notice definitions** in Koha. Define each transport notification template for each notice type.

**Important:** The below are Cut and Paste examples for SMS and Phone transport types for Hold, Overdue, Check-in and Check-out notices.  Make sure to copy the entire notice definition including the --- above and below. (Copy everything between the '''yaml and ''')

#### HOLD Notice Examples

**SMS Transport:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
hold: [% hold.reserve_id %]
sms:
  text: "[% branch.branchcode %]: [% IF holds.size > 1 %][% holds.size %] holds ready: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %]; [% END %][% END %][% ELSE %]Hold ready: [% biblio.title %][% END %]. Pickup by [% holds.0.expirationdate || hold.expirationdate | $KohaDates %]"
---
```

**Phone Transport:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
hold: [% hold.reserve_id %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. [% IF holds.size > 1 %][% holds.size %] items ready: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %], [% END %][% END %][% ELSE %]One item ready: [% biblio.title %][% END %]. Pickup by [% holds.0.expirationdate || hold.expirationdate | $KohaDates %]. Call 555-0100."
---
```

#### HOLDDGST (Hold Digest) Notice Examples

**Important:** HOLDDGST templates are designed for digest messages. The plugin automatically groups multiple individual HOLDDGST messages into single digest messages when patrons have digest preferences enabled.

**SMS Transport:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: [% IF holds && holds.size > 1 %]You have [% holds.size %] holds ready for pickup: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]. Pickup by [% holds.0.expirationdate | $KohaDates %][% ELSE %]Hold ready: [% biblio.title %]. Pickup by [% hold.expirationdate | $KohaDates %][% END %]."
---
```

**Phone Transport:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. You have [% IF holds && holds.size > 1 %][% holds.size %] holds ready for pickup: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %], [% END %][% END %]. Pickup by [% holds.0.expirationdate | $KohaDates %][% ELSE %]a hold ready for pickup: [% biblio.title %]. Pickup by [% hold.expirationdate | $KohaDates %][% END %]. Call 555-0100."
---
```

**How Digest Grouping Works:**
1. **Individual Messages**: Koha creates separate HOLDDGST messages for each hold
2. **Plugin Grouping**: Plugin automatically groups messages by patron and transport type
3. **Combined Output**: Multiple titles combined with semicolons (e.g., "The poems; Learning SQL")
4. **Updated Message Text**: Message content updated to show digest format
5. **CSV Result**: Single digest message instead of multiple individual messages

**Example CSV Output:**
```csv
S,default,HOLDDGST,,01234567890,Mr.,Yossi,Teichman,555-0101,example1@example.com,CPL,Centerville,1,2025-10-13,The poems; Learning SQL,,,,,52,,64,1,,,CPL: You have 2 holds ready for pickup: The poems; Learning SQL. Pickup by 10/20/2025.
```

#### CHECKOUT Notice Examples

**SMS Transport:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: [% IF checkouts.size > 1 %]Checked out [% checkouts.size %] items: [% FOREACH c IN checkouts %][% c.item.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]. All due [% checkouts.0.date_due | $KohaDates %][% ELSE %]Checked out: [% biblio.title %]. Due [% checkout.date_due | $KohaDates %][% END %]"
---
```

**Phone Transport:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. [% IF checkouts.size > 1 %]You checked out [% checkouts.size %] items: [% FOREACH c IN checkouts %][% c.item.biblio.title %][% UNLESS loop.last %], [% END %][% END %]. All due [% checkouts.0.date_due | $KohaDates %][% ELSE %]You checked out [% biblio.title %] due [% checkout.date_due | $KohaDates %][% END %]. Thank you!"
---
```

#### ODUE (Overdue) Notice Examples
**Important:** This is for ODUE.  If you want to have the multiple levels of ODUE messaging, create ODUE2 and ODUE3 Circulation Notices and customize accordingly.  Once all ODUE notices are defined, verify your Overdue notice/status triggers (** More > Tools > Overdue notice/status triggers **) are configured correctly to use these templates created.


**SMS Transport:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %] OVERDUE: [% biblio.title %] due [% issue.date_due | $KohaDates %]. Return now!"
---
```

**Phone Transport:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Overdue: [% biblio.title %] due [% issue.date_due | $KohaDates %]. Return immediately. 555-0100."
---
```

**Note:** ODUE templates use single-item format. Koha generates one message per overdue item. Use ODUE, ODUE2, ODUE3 letter codes for different notice levels.

#### CHECKIN (Item Returned) Notice Examples

**SMS Transport:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: The following items have been checked in: [% IF checkins.size > 1 %][% FOREACH c IN checkins %][% c.biblio.title %][% UNLESS loop.last %]; [% END %][% END %][% ELSE %][% biblio.title %][% END %]. Thank you."
---
```

**Phone Transport:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. The following item was checked in: [% IF checkins.size > 1 %][% FOREACH c IN checkins %][% c.biblio.title %][% UNLESS loop.last %], [% END %][% END %][% ELSE %][% biblio.title %][% END %]. Thank you!"
---
```

**Note:** 
- WhatsApp is configured as an SMS notice using the `whatsapp:` section.
- CHECKIN notices automatically populate `itemsID`, `biblionumber`, `title`, and `date` fields by extracting the title from the rendered message and matching it to recent check-ins in the database (last 24 hours).

#### PREDUE (Upcoming Due) Notice Examples

**PREDUE (Single Item) - SMS Transport:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: [% biblio.title %] is due [% issue.date_due | $KohaDates %]. Please return or renew."
---
```

**PREDUE (Single Item) - Phone Transport:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. [% biblio.title %] is due [% issue.date_due | $KohaDates %]. Please return or renew. Call 555-0100."
---
```

**PREDUEDGST (Digest) - SMS Transport:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: [% IF issues && issues.size > 1 %][% issues.size %] items due soon: [% FOREACH i IN issues %][% i.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]. Due [% issues.0.date_due | $KohaDates %][% ELSIF issues && issues.size == 1 %][% issues.0.biblio.title %] is due [% issues.0.date_due | $KohaDates %][% ELSE %][% biblio.title %] is due [% issue.date_due | $KohaDates %][% END %]. Please return or renew."
---
```

**PREDUEDGST (Digest) - Phone Transport:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. [% IF issues && issues.size > 1 %]You have [% issues.size %] items due soon: [% FOREACH i IN issues %][% i.biblio.title %][% UNLESS loop.last %], [% END %][% END %]. Due [% issues.0.date_due | $KohaDates %][% ELSIF issues && issues.size == 1 %][% issues.0.biblio.title %] is due [% issues.0.date_due | $KohaDates %][% ELSE %][% biblio.title %] is due [% issue.date_due | $KohaDates %][% END %]. Please return or renew. Call 555-0100."
---
```

**Note:** 
- PREDUE notices automatically populate `itemsID`, `biblionumber`, `title`, and `date` by matching the **rendered** SMS/phone text to the patron's upcoming due items (v1.1.46+). Each individual PREDUE row gets the item named in `messageText`, not always the earliest-due item.
- For digest messages (PREDUEDGST), the message text will show all items even if the template variables are empty.
- Use `advance_notices.pl` to generate PREDUE messages: `/usr/share/koha/bin/cronjobs/advance_notices.pl -c -v`

#### Additional Message Types

**HOLD_CHANGED (Hold Status Changed) - SMS:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Your hold for [% biblio.title %] has changed status. Check your account for details."
---
```

**HOLD_CHANGED (Hold Status Changed) - Phone:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Your hold for [% biblio.title %] has changed status. Please check your account for details. Call 555-0100."
---
```

**HOLD_CHANGEDGST (Hold Status Changed - Digest) - SMS:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: [% IF holds && holds.size > 1 %][% holds.size %] holds have changed status: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %]; [% END %][% END %][% ELSE %]Your hold for [% biblio.title %] has changed status[% END %]. Check your account for details."
---
```

**HOLD_CHANGEDGST (Hold Status Changed - Digest) - Phone:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. [% IF holds && holds.size > 1 %][% holds.size %] holds have changed status: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %], [% END %][% END %][% ELSE %]Your hold for [% biblio.title %] has changed status[% END %]. Please check your account for details. Call 555-0100."
---
```

**HOLD_REMINDER (Hold Reminder) - SMS:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Reminder: You have a hold for [% biblio.title %] ready for pickup. Expires [% hold.expirationdate | $KohaDates %]."
---
```

**HOLD_REMINDER (Hold Reminder) - Phone:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Reminder: You have a hold for [% biblio.title %] ready for pickup. Expires [% hold.expirationdate | $KohaDates %]. Call 555-0100."
---
```

**HOLD_REMINDERGST (Hold Reminder - Digest) - SMS:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Reminder: [% IF holds && holds.size > 1 %]You have [% holds.size %] holds ready for pickup: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]. Expires [% holds.0.expirationdate | $KohaDates %][% ELSE %]You have a hold for [% biblio.title %] ready for pickup. Expires [% hold.expirationdate | $KohaDates %][% END %]."
---
```

**HOLD_REMINDERGST (Hold Reminder - Digest) - Phone:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Reminder: [% IF holds && holds.size > 1 %]You have [% holds.size %] holds ready for pickup: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %], [% END %][% END %]. Expires [% holds.0.expirationdate | $KohaDates %][% ELSE %]You have a hold for [% biblio.title %] ready for pickup. Expires [% hold.expirationdate | $KohaDates %][% END %]. Call 555-0100."
---
```

**MEMBERSHIP_EXPIRY (Membership Expiring) - SMS:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Your membership expires [% borrower.dateexpiry | $KohaDates %]. Please renew to continue using library services."
---
```

**MEMBERSHIP_EXPIRY (Membership Expiring) - Phone:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Your membership expires [% borrower.dateexpiry | $KohaDates %]. Please renew to continue using library services. Call 555-0100."
---
```

**MEMBERSHIP_RENEWED (Membership Renewed) - SMS:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Your membership has been renewed. New expiry date: [% borrower.dateexpiry | $KohaDates %]. Thank you!"
---
```

**MEMBERSHIP_RENEWED (Membership Renewed) - Phone:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Your membership has been renewed. New expiry date: [% borrower.dateexpiry | $KohaDates %]. Thank you! Call 555-0100."
---
```

**RENEWAL (Item Renewed) - SMS:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: [% biblio.title %] has been renewed. New due date: [% issue.date_due | $KohaDates %]."
---
```

**RENEWAL (Item Renewed) - Phone:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. [% biblio.title %] has been renewed. New due date: [% issue.date_due | $KohaDates %]. Call 555-0100."
---
```

**RENEWALGST (Item Renewed - Digest) - SMS:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: [% IF issues && issues.size > 1 %][% issues.size %] items have been renewed: [% FOREACH i IN issues %][% i.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]. New due date: [% issues.0.date_due | $KohaDates %][% ELSE %][% biblio.title %] has been renewed. New due date: [% issue.date_due | $KohaDates %][% END %]."
---
```

**RENEWALGST (Item Renewed - Digest) - Phone:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. [% IF issues && issues.size > 1 %][% issues.size %] items have been renewed: [% FOREACH i IN issues %][% i.biblio.title %][% UNLESS loop.last %], [% END %][% END %]. New due date: [% issues.0.date_due | $KohaDates %][% ELSE %][% biblio.title %] has been renewed. New due date: [% issue.date_due | $KohaDates %][% END %]. Call 555-0100."
---
```

**WELCOME (New Member) - SMS:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Welcome to [% branch.branchname %]! Your library card number is [% borrower.cardnumber %]. Visit us soon!"
---
```

**WELCOME (New Member) - Phone:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. Welcome to [% branch.branchname %]! Your library card number is [% borrower.cardnumber %]. We're excited to have you as a member. Call 555-0100."
---
```

#### Account and Hold Message Types

**ACCOUNT_CREDIT (Account Credit) - SMS:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Credit of $[% account.amount %] applied to your account. Description: [% account.description %]. New balance: $[% account.amountoutstanding %]."
---
```

**ACCOUNT_DEBIT (Account Debit) - SMS:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Charge of $[% account.amount %] added to your account. Description: [% account.description %]. Outstanding balance: $[% account.amountoutstanding %]."
---
```

**ACCOUNT_PAYMENT (Payment Received) - SMS:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Payment of $[% account.amount %] received. Description: [% account.description %]. Outstanding balance: $[% account.amountoutstanding %]."
---
```

**ACCOUNT_WRITEOFF (Account Write-off) - SMS:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Account write-off of $[% account.amount %] processed. Description: [% account.description %]. Outstanding balance: $[% account.amountoutstanding %]."
---
```

**ACCOUNTS_SUMMARY (Account Summary) - SMS:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Account Summary - Outstanding balance: $[% account.total_balance %]. [% account.transaction_count %] outstanding transactions. Please pay at your convenience."
---
```

**HOLDPLACED (Hold Placed) - SMS:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Hold placed for [% biblio.title %]. You will be notified when ready for pickup. Expires [% hold.expirationdate | $KohaDates %]."
---
```

**HOLDPLACED_PATRON (Hold Placed - Patron) - SMS:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Hold placed for [% biblio.title %]. You will be notified when ready for pickup. Expires [% hold.expirationdate | $KohaDates %]."
---
```

**Note:** All additional message types automatically populate `itemsID`, `biblionumber`, `title`, and `date` fields by querying the appropriate database tables (reserves, borrowers, issues, accountlines).

### Step 7: Test Message Processing

- Create a few Hold Reservations and Checkin the items to create a Hold Notification.

Run the message queue processor:

```bash
sudo koha-shell INSTANCE -c "/usr/share/koha/bin/cronjobs/process_message_queue.pl"
```

Check the results:

```bash
ls -l /var/lib/koha/INSTANCE/CirriusImpact_archive/
tail -f /var/lib/koha/INSTANCE/CirriusImpact_archive/*.log
```

**Expected results:**
- ✅ No "regional phone numbers" error
- ✅ No "$self HASH" references in log
- ✅ CSV files created with message data
- ✅ Log files showing successful SFTP uploads
- ✅ All message fields populated (itemsID, title, phone, etc.)

**Check the output:**
```bash
# View CSV
cat ~/CirriusImpact_archive/*.csv | tail -10

# Check log
tail -50 ~/CirriusImpact_archive/*.log
```

## Verification

This was already done in Step 3 above, but lets re-run the verification to confirm:

```
✓ SMS::Send::US::CirriusImpact driver is installed (current)
✓ SMS::Send::CirriusImpact driver is installed (legacy)
✓ All required Perl modules found
✓ All plugin files present
✓ All checks passed!
```

**Note:** No Warnings should be present at this time.

## Driver Choice Guide

### Which Driver Should I Use?

**US::CirriusImpact** (Recommended for most users)
- ✅ Accepts: 555-0103, (731) 555-1212, +1 555-0103, +44...
- ✅ Works with: US regional AND international numbers
- ✅ No + prefix required
- ✅ Best for: US libraries, mixed environments

**CirriusImpact** (International only)
- ✅ Accepts: +1 555 0100, +44 20 1234 5678, +61...
- ❌ Requires: + prefix on ALL numbers
- ✅ Best for: Strictly international deployments

**Both drivers are automatically installed** when you upload the KPZ file. No manual installation required!

## Troubleshooting

### Error: "SMS::Send driver CirriusImpact does not exist" or "US::CirriusImpact does not exist"

**Note:** This warning is typically expected and can be safely ignored. The plugin uses the `before_send_messages` hook which runs before Koha's SMS::Send fallback mechanism.

**If you need to verify drivers are installed:**

The SMS drivers are automatically extracted when you install the KPZ. They should be at:
- `/var/lib/koha/{instance}/plugins/SMS/Send/CirriusImpact.pm`
- `/var/lib/koha/{instance}/plugins/SMS/Send/US/CirriusImpact.pm`

If they're missing, reinstall the plugin KPZ file. The drivers are included in the package and automatically extracted during installation.

### Error: "Cannot use regional phone numbers with an international driver"

**Cause:** Using `SMSSendDriver = 'CirriusImpact'` with numbers like 555-0100

**Fix:** Change to US driver:
```
SMSSendDriver = 'US::CirriusImpact'
```

### "SFTP FAILED"

**Check:**
- SFTP credentials in plugin configuration
- Network connectivity to SFTP host
- Port 222 is accessible

### No messages processed

**Check:**
1. Notice templates have `CirriusImpact: yes` header
2. Patron has SMS preferences enabled
3. Messages are in pending status

### Empty CSV files

**Check:**
1. Notice YAML is properly formatted
2. Patrons have contact information (phone/email)
3. Run with verbose mode:
   ```bash
   CirriusImpact_VERBOSE=1 sudo koha-shell INSTANCE -c "/usr/share/koha/bin/cronjobs/process_message_queue.pl"
   ```

## Support

- **Installation issues**: See INSTALL.md
- **Plugin configuration**: Contact ByWater Solutions
- **CirriusImpact service**: Contact CirriusImpact Support

## Next Steps

After successful installation:

1. **Set up patron preferences**: Ensure patrons have SMS numbers and preferences set
2. **Customize templates**: Adjust notice templates for your library's needs
3. **Schedule cronjob**: Add to crontab to run every 5 minutes
4. **Monitor logs**: Check archive directory regularly for issues

## Quick Reference

**Message Queue:**
```bash
# Run manually
sudo koha-shell INSTANCE -c "/usr/share/koha/bin/cronjobs/process_message_queue.pl"

# View recent logs
tail -20 /var/lib/koha/INSTANCE/CirriusImpact_archive/*.log | tail -20
```

**Check Messages:**
```bash
# List archive files
ls -ltr /var/lib/koha/INSTANCE/CirriusImpact_archive/

# View latest CSV
cat /var/lib/koha/INSTANCE/CirriusImpact_archive/*.csv | tail -1
```

**Test Mode:**
```bash
# Don't update message status (for testing)
CirriusImpact_TEST_MODE=1 sudo koha-shell INSTANCE -c "/usr/share/koha/bin/cronjobs/process_message_queue.pl"
```

---

**Version: 1.1.9  
**Updated:** October 11, 2025  
**Author:** Example User, CirriusImpact, LLC

