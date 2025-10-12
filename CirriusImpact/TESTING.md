# CirriusImpact Plugin - Complete Testing Guide

## Quick Start

Run the automated update and test script:

```bash
cd /var/lib/koha/library/plugins/Koha/Plugin/Com/ByWaterSolutions/CirriusImpact
sudo bash update_and_test.sh
```

This will:
- ✓ Update the SMS driver with all fixes
- ✓ Verify installation
- ✓ Test sends_to_anyone() method
- ✓ Test regional phone number support
- ✓ Display testing instructions

## All Fixes Applied

### Fix 1: $self HASH Bug ✅
**Problem:** Text contained `"Koha::Plugin::..::CirriusImpact=HASH(0x...)"`  
**Solution:** Updated `_ci_insert_title_into_text()` to handle both method and function call styles

### Fix 2: CHECKOUT Message Backfill ✅
**Problem:** CHECKOUT messages had empty itemsID, biblionumber, title  
**Solution:** Created `_ci_backfill_checkout_identifiers()` function that queries Koha's issues table

### Fix 3: Phone Message Backfill ✅
**Problem:** Backfill only worked for SMS, not phone messages  
**Solution:** Modified both backfill functions to loop through all transport sections (call, sms, email, whatsapp)

### Fix 4: Regional Phone Numbers ✅
**Problem:** Error "Cannot use regional phone numbers with an international driver"  
**Solution:** Added `sends_to_anyone()` method to SMS driver

## Testing Steps

### 1. Update the System

```bash
cd /var/lib/koha/library/plugins/Koha/Plugin/Com/ByWaterSolutions/CirriusImpact
sudo bash update_and_test.sh
```

Expected output:
```
✓ Running with sudo privileges
✓ Driver updated
✓ Driver loads successfully
✓ sends_to_anyone() method exists and returns true
✓ Regional phone number accepted: 7325861275
```

### 2. Test CHECKOUT Messages

**Scenario A: Check out items**
```bash
# In Koha staff interface:
# 1. Check out 1-2 items to a patron
# 2. Patron should have SMS preferences configured

# Run message queue
sudo koha-shell library -c "/usr/share/koha/bin/cronjobs/process_message_queue.pl"
```

**What to verify:**
```bash
# Check latest CSV
cat ~/CirriusImpact_archive/*.csv | tail -5

# Look for:
# - commType: S or V
# - notificationType: CHECKOUT
# - itemsID: populated (e.g., 413)
# - title: populated (e.g., "The poems")
# - phone: populated without errors
```

Expected CSV line:
```csv
S,default,CHECKOUT,,01234567890,,Yossi,Teichman,7325861275,yossit@cgstogo.com,CPL,Centerville,413,2025-10-18 23:59:00,The poems,,,,,52,,29,1,,
```

### 3. Test ODUE Messages

**Scenario B: Overdue notices**
```bash
# Generate overdue notices
/usr/share/koha/bin/cronjobs/overdue_notices.pl

# Process messages
sudo koha-shell library -c "/usr/share/koha/bin/cronjobs/process_message_queue.pl"
```

**What to verify:**
```bash
# Check log for backfill messages
tail -100 ~/CirriusImpact_archive/*.log | grep "Backfill"

# Should see:
# "Backfill ODUE: Set title to '...' for message section=sms"
# "Backfill ODUE: Set title to '...' for message section=call"
```

### 4. Test Phone Messages

**Scenario C: Phone/Voice messages**
```bash
# Ensure patron has phone transport preference set
# Trigger notice (hold ready, checkout, etc.)

# Process messages
sudo koha-shell library -c "/usr/share/koha/bin/cronjobs/process_message_queue.pl"
```

**What to verify:**
```bash
# Check CSV for commType=V (Voice)
cat ~/CirriusImpact_archive/*.csv | grep "^V,"

# Should see:
# - itemsID populated
# - title populated
# - phone number present
```

Example:
```csv
V,default,CHECKOUT,,001,,Terry,Rossio,7325553663,tcr@cgstogo.com,CPL,Centerville,413,2025-10-18,The poems,,,,,51,,,,,
```

### 5. Check for Errors

**No errors expected:**
```bash
tail -50 ~/CirriusImpact_archive/*.log | grep -i error
```

Should return **empty** or only show:
- SMTP errors (configuration issue, not plugin bug)

**Should NOT see:**
- ❌ "regional phone numbers" error
- ❌ "$self HASH" in text
- ❌ Empty itemsID for CHECKOUT messages

## What Success Looks Like

### ✅ Successful Test Results

**1. No Errors in Log:**
```bash
tail -100 ~/CirriusImpact_archive/*.log
```
Should show:
```
✓ CI SMS FINAL: ... (no HASH references)
✓ Backfill CHECKOUT: Set title to '...' section=sms
✓ Backfill CHECKOUT: Set title to '...' section=call
✓ CI - FILE WRITTEN TO ...
✓ CI - SFTP PUT ...
```

**2. Complete CSV Data:**
```bash
cat ~/CirriusImpact_archive/*.csv | tail -5
```
Should show all fields populated:
- commType: S or V
- itemsID: numbers (not empty)
- title: book titles (not empty)
- phone: phone numbers

**3. Text Fields Clean:**
```bash
tail -100 ~/CirriusImpact_archive/*.log | grep "text.*=>"
```
Should show normal text like:
```
'text' => '[Centerville] Yossi, You have item(s)...'
```

Should NOT show:
```
'text' => 'Koha::Plugin::...::HASH(0x...)'  # BAD!
```

## Troubleshooting

### Problem: "Cannot use regional phone numbers"

**Solution:**
```bash
# Verify sends_to_anyone method exists
perl -MSMS::Send::CirriusImpact -e 'my $s = SMS::Send->new("CirriusImpact"); print $s->sends_to_anyone ? "OK\n" : "MISSING\n"'

# Should output: OK
```

If output is "MISSING", re-run:
```bash
sudo bash update_and_test.sh
```

### Problem: Empty itemsID for CHECKOUT

**Check log for backfill:**
```bash
tail -100 ~/CirriusImpact_archive/*.log | grep "Backfill CHECKOUT"

# Should see:
# "Backfill CHECKOUT: Set title to '...' section=..."
```

If not found:
- Plugin file may not have the fix
- Re-upload the plugin KPZ

### Problem: $self HASH still in text

**Check plugin version:**
```bash
grep "our \$VERSION" /var/lib/koha/library/plugins/Koha/Plugin/Com/ByWaterSolutions/CirriusImpact.pm

# Should show: our $VERSION = "1.1.6";
```

If fix is missing, the plugin file needs to be updated.

## Complete Test Checklist

- [ ] Run `sudo bash update_and_test.sh` - all tests pass
- [ ] Check out item - CHECKOUT message generated
- [ ] CHECKOUT CSV has itemsID and title populated
- [ ] Generate ODUE notices - messages processed
- [ ] ODUE CSV has itemsID and title populated
- [ ] Phone messages have itemsID and title
- [ ] No "regional phone numbers" error in log
- [ ] No "$self HASH" references in text
- [ ] CSV export contains complete data
- [ ] SFTP upload successful (check log)

## Files Modified

**Plugin Files:**
- `CirriusImpact.pm` - Main plugin (4 fixes applied)
- `sms_driver/SMS/Send/CirriusImpact.pm` - Bundled driver

**System Files:**
- `/usr/share/perl5/SMS/Send/CirriusImpact.pm` - System driver

**New Files:**
- `update_and_test.sh` - Automated update script
- `TESTING.md` - This file

## Getting Help

If tests fail:

1. Check the log file:
   ```bash
   tail -100 ~/CirriusImpact_archive/*.log
   ```

2. Verify driver installation:
   ```bash
   perl -MSMS::Send::CirriusImpact -e 'print "OK\n"'
   ```

3. Check plugin version:
   ```bash
   grep VERSION /var/lib/koha/library/plugins/Koha/Plugin/Com/ByWaterSolutions/CirriusImpact.pm
   ```

4. Re-run update:
   ```bash
   sudo bash update_and_test.sh
   ```

## Expected Timeline

- Update & verify: 1 minute
- Test CHECKOUT: 2-3 minutes  
- Test ODUE: 2-3 minutes
- Test phone messages: 2-3 minutes
- **Total: ~10 minutes**

## Success Criteria

All fixes are working when:
1. ✅ No errors in process_message_queue.pl output
2. ✅ CSV files have complete data (itemsID, title, phone)
3. ✅ Log shows backfill messages for all sections
4. ✅ Phone numbers work with or without + prefix
5. ✅ No HASH references in text fields

---

**Version: 1.1.7  
**Last Updated:** October 11, 2025  
**Author: Terry Rossio, CirriusImpact









