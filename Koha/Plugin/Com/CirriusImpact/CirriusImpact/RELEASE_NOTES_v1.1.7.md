
# CirriusImpact Plugin - Release Notes v1.1.7

**Release Date:** October 11, 2025  
**Plugin Version:** 1.1.7  
**SMS Driver Version:** 1.0.1  

## Overview

Version 1.1.7 is a major update that introduces the SMS::Send driver integration, fixes critical bugs, adds CHECKOUT message backfill, and provides comprehensive notice template examples including digest formats.

## 🎯 Key Improvements

### 1. SMS::Send Driver Integration (Major)
- **New Driver**: SMS::Send::US::CirriusImpact
- **Location**: `/usr/share/perl5/SMS/Send/US/CirriusImpact.pm`
- **Phone Numbers**: Accepts both regional (555-0100) and international (+44...) formats
- **Installation**: Automated via `install_sms_driver.pl`
- **Verification**: Built-in testing with `verify_installation.pl`

**Configuration Change:**
```
Old: SMSSendDriver = 'CirriusImpact'
New: SMSSendDriver = 'US::CirriusImpact'
```

### 2. Critical Bug Fixes (4)

#### Bug #1: $self Object Interpolation
**Symptom:** Text fields contained `"Koha::Plugin::...::HASH(0x...)"`  
**Impact:** Messages were corrupted  
**Fix:** Updated `_ci_insert_title_into_text()` to handle both method and function calls  
**Status:** ✅ FIXED

#### Bug #2: Phone Messages Missing Data
**Symptom:** Phone ODUE/CHECKOUT messages had empty itemsID and title  
**Impact:** Incomplete CSV exports  
**Fix:** Backfill now checks all transport sections after they're created  
**Status:** ✅ FIXED

#### Bug #3: Regional Phone Number Validation
**Symptom:** Error "Cannot use regional phone numbers with an international driver"  
**Impact:** Messages failed to process  
**Fix:** Changed to US::CirriusImpact driver (accepts regional format)  
**Status:** ✅ FIXED

#### Bug #4: CHECKOUT Messages Missing Item Data
**Symptom:** CHECKOUT messages had empty itemsID, biblionumber, title  
**Impact:** CSV missing critical data  
**Fix:** Created `_ci_backfill_checkout_identifiers()` function  
**Status:** ✅ FIXED

### 3. CHECKOUT Message Backfill (New Feature)
- Automatically populates item data for CHECKOUT messages
- Queries Koha's issues table for active checkouts
- Fills in: itemsID, biblionumber, title, date_due
- Uses message_id to distribute across multiple checkouts
- Works for both SMS and phone transports

### 4. Enhanced Backfill System
- **Before**: Only checked SMS section, relied on database transport type
- **After**: Checks all sections (call, sms, email, whatsapp) that actually exist
- **Timing**: Runs after each transport section is fully created
- **Coverage**: Works reliably for all message types and transports

### 5. Comprehensive Documentation (9 Files)

1. **README.md** - Updated overview with installation steps
2. **CHANGELOG.md** - Complete version history with v1.1.7 details
3. **INSTALL.md** - Detailed installation guide (6.9KB)
4. **QUICKSTART.md** - 5-minute setup guide (5.8KB)
5. **TESTING.md** - Complete testing procedures (7.3KB)
6. **NOTICE_EXAMPLES.md** - 30+ template examples (27KB) **NEW**
7. **DIGEST_QUICK_REFERENCE.md** - Quick digest reference (8KB) **NEW**
8. **INTERNATIONAL_SUPPORT.md** - International phone guide (5.2KB)
9. **FIXES_APPLIED.md** - All fixes documented (6.8KB)

### 6. Notice Template Examples (30+)

#### CHECKOUT Digest Examples (10)
- Single item per message
- All items in one message (digest)
- Formatted bullet lists
- Numbered lists
- Multi-transport (SMS + Phone + Email)
- Compact format for long lists
- Conditional based on item count
- With item types
- With renewal information
- Advanced conditional logic

#### HOLD Digest Examples (10)
- Single hold per message
- All holds in one message (digest)
- Formatted lists with expiration dates
- Numbered lists
- Compact format for many holds
- Multi-transport examples
- With pickup locations
- Different formats per branch
- Conditional based on hold count
- With multiple branch support

#### ODUE Digest Examples (10)
- Single overdue per message
- All overdues in one message (digest)
- Formatted lists with due dates
- With days overdue count
- With fine amounts
- Escalating urgency (ODUE/ODUE2/ODUE3)
- Compact format for many overdues
- Multi-transport examples
- Grouped by severity
- With account suspension warnings

### 7. Automated Installation & Testing

**New Scripts:**
- `install_sms_driver.pl` - Automated driver installation
- `verify_installation.pl` - Complete installation verification
- `update_and_test.sh` - Update and test all components

**Features:**
- Color-coded output (✓ success, ✗ error, ⚠ warning, ℹ info)
- Automatic system detection
- Root privilege checking
- Comprehensive testing
- Clear next-step instructions

## 📦 Package Contents

**Total:** 22 files (~150KB)

**Core Plugin:** 1 file (76KB)
**Documentation:** 9 markdown files (75KB)
**Scripts:** 3 executable scripts (24KB)
**Drivers:** 2 SMS::Send drivers (6KB)
**Configuration:** 2 templates (9KB)
**API:** 1 file (2KB)
**Metadata:** 4 text files (15KB)

## 🔧 Breaking Changes

### ⚠️ Configuration Update Required

**You MUST update your Koha system preference:**

```
Administration > Global System Preferences > Patrons
SMSSendDriver = 'US::CirriusImpact'
```

**Why the change?**
- US regional driver accepts phone numbers without + prefix
- Still works with international numbers (+44, +61, etc.)
- Prevents "regional phone numbers" validation error

### Migration Path

**From v1.1.6 or earlier:**
1. Upload v1.1.7 KPZ
2. Run: `sudo perl install_sms_driver.pl`
3. Update SMSSendDriver preference to 'US::CirriusImpact'
4. Test: `sudo koha-shell INSTANCE -c '/usr/share/koha/bin/cronjobs/process_message_queue.pl'`

## 🧪 Testing Results

All fixes verified with real-world testing:
- ✅ HOLD messages: 4/4 complete
- ✅ CHECKOUT messages: itemsID and title populated
- ✅ ODUE messages: All levels working
- ✅ Phone numbers: Regional format accepted
- ✅ No $self HASH bugs
- ✅ CSV export: Complete data

## 📚 Documentation Improvements

### New Guides
- Installation procedures (automated and manual)
- International phone number support
- 30+ ready-to-use notice templates
- Digest notice quick reference
- Complete testing procedures

### Enhanced Examples
- Copy-paste ready templates
- Real-world output examples
- Multi-transport configurations
- Troubleshooting guides

## 🌍 International Support

The US::CirriusImpact driver works internationally:
- ✅ US regional: 555-0100, 555-0100
- ✅ US international: +1 555 0100
- ✅ UK: +44 20 1234 5678
- ✅ Australia: +61 2 1234 5678
- ✅ Any country code: +XX...

See `INTERNATIONAL_SUPPORT.md` for complete details.

## 🚀 New Features Summary

1. **SMS Driver** - Full SMS::Send integration
2. **CHECKOUT Backfill** - Auto-populate item data
3. **Enhanced Backfill** - Works for all transports
4. **Digest Templates** - 30+ examples
5. **Automated Scripts** - Install, verify, update
6. **Documentation** - 9 comprehensive guides
7. **International** - Worldwide phone support
8. **Bug Fixes** - 4 critical issues resolved

## 📝 Upgrade Notes

### For New Installations
1. Follow `QUICKSTART.md` for 5-minute setup
2. Use `NOTICE_EXAMPLES.md` for template ideas
3. Run `verify_installation.pl` to confirm setup

### For Existing Installations
1. Upload v1.1.7 KPZ
2. Run `sudo perl install_sms_driver.pl`
3. Update SMSSendDriver to 'US::CirriusImpact'
4. Review `FIXES_APPLIED.md` for changes
5. Consider using digest templates from `NOTICE_EXAMPLES.md`

## 🐛 Known Issues

**SMTP Connection Error:**
- Non-CirriusImpact email messages may trigger SMTP errors
- This is a Koha configuration issue, not a plugin bug
- Fix: `sudo koha-email-enable INSTANCE`
- Or: Add `CirriusImpact: yes` to all email notices

## 💡 Recommendations

1. **Use Digest Templates** - Combine multiple items into one message
2. **Test Installation** - Run `verify_installation.pl` after upload
3. **Review Examples** - See `NOTICE_EXAMPLES.md` for best practices
4. **Enable Logging** - Monitor `CirriusImpact_archive/*.log`
5. **Configure SMTP** - Avoid SMTP errors for non-CirriusImpact messages

## 📞 Support

- **Installation Issues**: See `INSTALL.md` or `TROUBLESHOOTING` section
- **Notice Templates**: See `NOTICE_EXAMPLES.md`
- **Digest Syntax**: See `DIGEST_QUICK_REFERENCE.md`
- **International Support**: See `INTERNATIONAL_SUPPORT.md`
- **Bug Reports**: Contact ByWater Solutions
- **Service Issues**: Contact CirriusImpact Support

## 🎉 Conclusion

Version 1.1.7 represents a major improvement in stability, functionality, and usability:
- All critical bugs fixed
- Complete documentation suite
- 30+ ready-to-use templates
- Automated installation tools
- International phone support
- Enhanced data backfill

**This release is production-ready and recommended for all users.**

---

**Full changelog:** See `CHANGELOG.md`  
**Installation:** See `INSTALL.md` or `QUICKSTART.md`  
**Examples:** See `NOTICE_EXAMPLES.md`  
**Testing:** See `TESTING.md`

