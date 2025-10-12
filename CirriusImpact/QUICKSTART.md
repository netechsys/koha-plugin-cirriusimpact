# CirriusImpact Plugin - Quick Start Guide

## Overview

**International Support:** This plugin works with phone numbers in any format - US (+1), UK (+44), Australia (+61), or regional formats. The SMS::Send driver accepts international and local number formats.

## Installation (10 minutes)

### Step 1: Upload Plugin to Koha

1. Go to **Tools > Plugins > Upload Plugin**
2. Select `CirriusImpact-v1.1.7.kpz`
3. Click **Upload**
4. Wait for upload to complete

### Step 2: Install SMS Drivers (Both Drivers)

Navigate to the plugin directory and run the installer:

```bash
cd /var/lib/koha/library/plugins/Koha/Plugin/Com/ByWaterSolutions/CirriusImpact/
sudo perl install_sms_driver.pl
```

The installer will automatically install **BOTH** drivers:

**Expected output:**
```
✓ Installing US::CirriusImpact (regional + international)
✓ US::CirriusImpact driver installed
✓ Installing CirriusImpact (international compatibility)
✓ CirriusImpact driver installed
✓ US::CirriusImpact driver loaded successfully
✓ CirriusImpact driver loaded successfully
✓ US::CirriusImpact driver test passed
✓ CirriusImpact driver test passed

Installation Complete!
```

**What gets installed:**
- `/usr/share/perl5/SMS/Send/US/CirriusImpact.pm` (regional + international)
- `/usr/share/perl5/SMS/Send/CirriusImpact.pm` (international only)

### Step 3: Configure Koha System Preference

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

### Step 4: Verify Installation

Run the verification script:

```bash
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

**Common warnings (both are normal):**
- ⚠ Archive directory not found → **Will be created automatically on first run**

### Step 5: Configure Plugin

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
4. Click **Save**

### Step 6: Configure Notice Templates

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
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. [% IF holds.size > 1 %][% holds.size %] items ready: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %], [% END %][% END %][% ELSE %]One item ready: [% biblio.title %][% END %]. Pickup by [% holds.0.expirationdate || hold.expirationdate | $KohaDates %]. Call [% branch.branchphone %]."
---
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
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Overdue: [% biblio.title %] due [% issue.date_due | $KohaDates %]. Return immediately. [% branch.branchphone %]."
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
- ✅ Accepts: 7325551212, (732) 555-1212, +1 732 555 1212, +44...
- ✅ Works with: US regional AND international numbers
- ✅ No + prefix required
- ✅ Best for: US libraries, mixed environments

**CirriusImpact** (International only)
- ✅ Accepts: +1 732 586 1275, +44 20 1234 5678, +61...
- ❌ Requires: + prefix on ALL numbers
- ✅ Best for: Strictly international deployments

**Both drivers are installed automatically** by `install_sms_driver.pl`

## Troubleshooting

### Error: "SMS::Send driver CirriusImpact does not exist" or "US::CirriusImpact does not exist"

**Fix:** Install both drivers:
```bash
cd /var/lib/koha/library/plugins/Koha/Plugin/Com/ByWaterSolutions/CirriusImpact/
sudo perl install_sms_driver.pl
```

This automatically installs BOTH US::CirriusImpact and CirriusImpact.

### Error: "Cannot use regional phone numbers with an international driver"

**Cause:** Using `SMSSendDriver = 'CirriusImpact'` with numbers like 7325861275

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
**Author:** Terry Rossio, CirriusImpact, LLC

