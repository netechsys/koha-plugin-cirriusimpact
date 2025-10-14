# CirriusImpact Koha Plugin

[![Version](https://img.shields.io/badge/version-1.1.16-blue.svg)](https://github.com/netechsys/koha-plugin-cirriusimpact/releases/tag/v1.1.16)
[![License](https://img.shields.io/badge/license-GPL--3.0-green.svg)](LICENSE)
[![Koha](https://img.shields.io/badge/Koha-Compatible-orange.svg)](https://koha-community.org/)

**Production-ready Koha plugin for automated patron messaging via SMS, Phone Calls, Email, and WhatsApp with CSV export to CirriusImpact API.**

---

## 📋 Table of Contents

- [Features](#features)
- [What's New in v1.1.16](#whats-new-in-v116)
- [Quick Start](#quick-start)
- [Installation](#installation)
- [Documentation](#documentation)
- [Supported Message Types](#supported-message-types)
- [Testing & Validation](#testing--validation)
- [Download](#download)
- [Support](#support)
- [License](#license)

---

## ✨ Features

### 📱 **Multi-Channel Messaging**
- **SMS** - Text messages via CirriusImpact SMS gateway
- **Phone/Voice** - Automated voice calls with custom scripts
- **Email** - Traditional email notifications
- **WhatsApp** - WhatsApp messages (configured as SMS)

### 📬 **Message Types**
- **HOLD** - Hold ready notifications (digest)
- **HOLDDGST** - Hold digest notifications (automatic grouping)
- **CHECKOUT** - Item checkout confirmations (digest)
- **CHECKIN** - Item return confirmations (digest)
- **ODUE/ODUE2/ODUE3** - Overdue reminders (single-item)
- **PREDUE/PREDUEDGST** - Pre-due notifications (digest)
- **HOLDPLACED** - Hold placement confirmations
- **HOLDPLACED_PATRON** - Hold confirmation notices
- **HOLD_CHANGED** - Hold status change notifications
- **HOLD_REMINDER** - Hold reminder notifications
- **RENEWAL** - Item renewal notifications

### 🔄 **Intelligent Processing**
- **Digest Support** - Combine multiple items into single messages
- **Individual Messages** - Send separate messages per item
- **Patron Preferences** - Respects patron messaging preferences
- **ODUE Suppression** - Skip phone ODUE if patron has SMS/Email enabled
- **Auto-Population** - Automatically fills CSV fields (itemsID, title, date, etc.)
- **Module Assignment** - Correct template module assignments (HOLD → reserves, ODUE → circulation)

### 📊 **CSV Export**
- **26 Complete Fields** - All required data for CirriusImpact API
- **Automatic Backfilling** - Enriches message data with item details
- **Title Matching** - Extracts and matches titles from messages
- **SFTP Upload** - Automated transfer to CirriusImpact
- **Configurable messageText** - Optional inclusion of full message content
- **Validated Output** - Comprehensive testing across all message types

---

## 🆕 What's New in v1.1.16

### **Critical Module Assignment Fix**
✅ **FIXED**: HOLD templates now correctly assigned to 'reserves' module instead of 'circulation' module  
✅ **ROOT CAUSE**: Phone messages were not being generated due to incorrect module assignments  
✅ **SOLUTION**: Updated install_message_templates.pl with correct module assignments:
- HOLD* templates → 'reserves' module
- ODUE* templates → 'circulation' module (unchanged)
- PREDUE* templates → 'circulation' module (unchanged)

### **Template Coverage Improvements**
✅ **ADDED**: Missing HOLDPLACED and HOLDPLACED_PATRON templates  
✅ **ADDED**: HOLD_SLIP_EMAIL template in circulation module  
✅ **COMPLETE**: All default Koha message types now have CirriusImpact templates  
✅ **ENHANCED**: Direct database connection fallback for installer script  
✅ **TESTED**: Verified phone messaging now works correctly for patron 51

### **Message Template Installer**
✅ **NEW**: Added `install_message_templates.pl` script for automatic template installation  
✅ **30+ Templates**: Installs pre-configured templates for all supported message types  
✅ **Complete Coverage**: Includes HOLD, CHECKOUT, CHECKIN, ODUE, PREDUE, and membership templates  
✅ **SMS & Phone**: All templates include both SMS and Phone transport versions  
✅ **CirriusImpact Ready**: All templates include proper YAML markers and CirriusImpact integration  
✅ **Easy Installation**: Single command installs all templates: `sudo perl install_message_templates.pl`

### **MessageText Configuration Option**
✅ **NEW**: Added configuration checkbox to enable/disable messageText column in CSV output  
✅ **Flexible Output**: Users can choose whether to include full message content in CSV files  
✅ **Configuration UI**: Added "Include messageText column in CSV output" checkbox in plugin configuration  
✅ **Conditional Processing**: CSV generation now checks configuration before including messageText column  
✅ **Backward Compatible**: Default behavior maintains current functionality

---

## 🚀 Quick Start

### **Installation** (5 minutes)

```bash
# 1. Download the plugin
wget https://github.com/netechsys/koha-plugin-cirriusimpact/archive/refs/tags/v1.1.16.zip

# 2. Install in Koha
# Upload via: Administration → Plugins → Upload plugin

# 3. Install SMS drivers
cd /var/lib/koha/[INSTANCE]/plugins/Koha/Plugin/Com/ByWaterSolutions/CirriusImpact/
sudo perl install_sms_driver.pl

# 4. Install message templates (recommended)
sudo perl install_message_templates.pl

# 5. Configure Koha
# Set: SMSSendDriver = 'US::CirriusImpact'
# Set: PhoneSendDriver = 'US::CirriusImpact'
# (Administration → Global System Preferences → Patrons)
```

### **Configure Plugin** (3 minutes)

1. Go to: **Administration → Plugins → CirriusImpact → Actions → Configure**
2. Fill in:
   - SFTP Host
   - SFTP Username
   - SFTP Password
   - SFTP Path
   - Archive Directory
3. Enable: **Skip calling ODUE if patron has SMS or Email** ✓
4. Enable: **Include messageText column in CSV output** (optional) ✓
5. Click **Save Configuration**

### **Test Installation** (2 minutes)

1. Create a test hold for a patron with phone number
2. Run: `/usr/share/koha/bin/cronjobs/process_message_queue.pl`
3. Check: `/var/lib/koha/[INSTANCE]/CirriusImpact_archive/` for CSV files
4. Verify: Phone messages are generated correctly

**Ready to use!** 🎉

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| **[QUICKSTART.md](CirriusImpact/QUICKSTART.md)** | 10-minute setup guide with copy-paste templates |
| **[INSTALL.md](CirriusImpact/INSTALL.md)** | Detailed installation instructions |
| **[NOTICE_EXAMPLES.md](CirriusImpact/NOTICE_EXAMPLES.md)** | 35+ template examples for all message types |
| **[TEMPLATE_FORMAT.md](CirriusImpact/TEMPLATE_FORMAT.md)** | YAML template syntax reference |
| **[DIGEST_VS_INDIVIDUAL.md](CirriusImpact/DIGEST_VS_INDIVIDUAL.md)** | Digest vs individual messaging guide |
| **[CHANGELOG.md](CirriusImpact/CHANGELOG.md)** | Version history and changes |
| **[TESTING_RESULTS_v1.1.9.md](CirriusImpact/TESTING_RESULTS_v1.1.9.md)** | Complete test validation |

### **Quick Reference Guides**
- [DIGEST_QUICK_REFERENCE.md](CirriusImpact/DIGEST_QUICK_REFERENCE.md) - Digest message format
- [INTERNATIONAL_SUPPORT.md](CirriusImpact/INTERNATIONAL_SUPPORT.md) - International phone formats
- [DUAL_DRIVER_INFO.md](CirriusImpact/DUAL_DRIVER_INFO.md) - US vs International drivers

---

## 📬 Supported Message Types

### **HOLD Notices** (Digest Format)
- **Multiple holds** combined into one message
- **Patron preferences** determine SMS, Phone, or both
- **Expiration dates** included automatically
- **Example**: "CPL: 3 holds ready: Learning SQL; The poems; The bible. Pickup by 10/20/2025"

### **HOLDDGST Notices** (Automatic Digest)
- **Automatic grouping** of multiple individual HOLDDGST messages
- **Combined titles** with semicolon separation
- **Updated message text** to show digest format
- **Example**: "You have 2 holds ready for pickup: Title 1; Title 2. Pickup by 10/20/2025"

### **CHECKOUT Notices** (Digest Format)
- **Multiple checkouts** combined into one message
- **Due dates** shown for all items
- **Automatic itemsID population** via backfill
- **Example**: "Checked out 3 items: Learning SQL; The poems; The bible. All due 10/25/2025"

### **CHECKIN Notices** (Digest Format)
- **Multiple check-ins** combined into one message
- **Return confirmation** for patron peace of mind
- **Automatic field population** (itemsID, title, date)
- **Example**: "The following items have been checked in: Learning SQL; The poems. Thank you."

### **ODUE Notices** (Single-Item Format)
- **One message per overdue item** (not digest)
- **Escalation levels**: ODUE, ODUE2, ODUE3
- **Smart suppression**: Skip phone if patron has SMS
- **Example**: "CPL OVERDUE: Learning SQL due 10/05/2025. Return now!"

### **PREDUE Notices** (Digest Format)
- **Pre-due notifications** before items become overdue
- **Multiple items** combined into single message
- **Due date reminders** for upcoming returns
- **Example**: "Reminder: 2 items due soon: Title 1; Title 2. Please return or renew."

---

## ✅ Testing & Validation

### **Production Tested**
- ✅ **All message types** processed successfully
- ✅ **Multiple notice types** (HOLD, HOLDDGST, CHECKOUT, CHECKIN, ODUE, PREDUE)
- ✅ **All transports** (SMS + Phone + Email)
- ✅ **26 CSV fields** validated
- ✅ **Module assignments** verified (HOLD → reserves, ODUE → circulation)
- ✅ **Phone messaging** working correctly

### **Critical Fixes Validated**
- ✅ **HOLD templates** correctly assigned to 'reserves' module
- ✅ **Phone messages** now generated for HOLD notifications
- ✅ **Template installer** working with direct database connection
- ✅ **Complete template coverage** for all message types

### **CSV Field Validation**
All 26 fields verified:
- ✅ `commType`, `language`, `notificationType`, `notificationLevel`
- ✅ `patronBarCode`, `STAB_userSalutation`, `patronFirstName`, `patronLastName`, `phone`, `email`
- ✅ `branch`, `branchname`
- ✅ `itemsID`, `biblionumber`, `title`, `date`
- ✅ `DeliveryOptionID`, `LanguageID`, `NotificationTypeID`, `ReportingOrgID`
- ✅ `PatronID`, `ItemRecordID`, `RequestID`, `TxnID`
- ✅ `PickupAreaDescription`, `AccountBalance`
- ✅ `messageText` (SMS text or Phone script) - **Configurable**

---

## 📥 Download

### **Latest Release: v1.1.16**

**Direct Download:**
- **GitHub Release**: [v1.1.16](https://github.com/netechsys/koha-plugin-cirriusimpact/releases/tag/v1.1.16)
- **Archive**: [Download ZIP](https://github.com/netechsys/koha-plugin-cirriusimpact/archive/refs/tags/v1.1.16.zip)

**What's Included:**
- 1 main plugin file (`CirriusImpact.pm` v1.1.16)
- 2 SMS drivers (US::CirriusImpact, CirriusImpact)
- 1 message template installer (`install_message_templates.pl`)
- 12+ documentation files
- 2 installation scripts
- 1 configuration template

**Package Size:** 104KB  
**Files:** 30+ total  
**Release Date:** October 14, 2025

---

## 🔧 System Requirements

- **Koha Version**: 20.05 or later (tested on 23.x)
- **Perl**: 5.26 or later
- **Dependencies**: 
  - `Net::SFTP::Foreign` (for SFTP upload)
  - `YAML::XS` (for template parsing)
  - `SMS::Send` (for SMS functionality)
  - `DBI` (for database connections)
- **Permissions**: Write access to plugin directories

---

## 📖 Template Format

Templates use **YAML format** with **Template Toolkit (TT)** logic:

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "Your message with [% variables %]"
call:
  script: "Hello [% borrower.firstname %]. Your message with [% variables %]"
---
```

**Key Features:**
- `---` markers required at start and end
- Separate SMS and Phone templates (no mixed types)
- Template Toolkit variables: `[% borrowernumber %]`, `[% biblio.title %]`, etc.
- Conditional logic: `[% IF holds.size > 1 %]...[% END %]`
- Loops: `[% FOREACH h IN holds %]...[% END %]`
- Date formatting: `[% date | $KohaDates %]`

See [TEMPLATE_FORMAT.md](CirriusImpact/TEMPLATE_FORMAT.md) for complete reference.

---

## 🛡️ Known Issues & Workarounds

### **Koha Template Toolkit `.size` Bug**

**Issue:**  
Koha's Template Toolkit has a bug with `.size` method on `Koha::Objects` collections in ODUE notice context, causing error:
```
The method Koha::Checkouts->size is not covered by tests!
```

**Workaround:**  
Use simplified single-item ODUE templates without `.size` calls. Templates updated in `QUICKSTART.md` and `NOTICE_EXAMPLES.md`.

**Impact:**
- ODUE messages use single-item format (one message per overdue item)
- HOLD, CHECKOUT, CHECKIN still use digest format
- All message types work correctly with this approach

### **Module Assignment Requirements**

**Issue:**  
HOLD templates must be assigned to the 'reserves' module, not 'circulation' module.

**Solution:**  
The `install_message_templates.pl` script now correctly assigns:
- HOLD* templates → 'reserves' module
- ODUE* templates → 'circulation' module
- PREDUE* templates → 'circulation' module

---

## 🤝 Support

### **Documentation**
- **Quick Start**: [QUICKSTART.md](CirriusImpact/QUICKSTART.md)
- **Examples**: [NOTICE_EXAMPLES.md](CirriusImpact/NOTICE_EXAMPLES.md)
- **Installation**: [INSTALL.md](CirriusImpact/INSTALL.md)
- **Testing**: [TESTING_RESULTS_v1.1.9.md](CirriusImpact/TESTING_RESULTS_v1.1.9.md)

### **Troubleshooting**
See [QUICKSTART.md - Troubleshooting](CirriusImpact/QUICKSTART.md#troubleshooting) section for common issues and solutions.

### **Contact**
- **GitHub Issues**: [Report a bug](https://github.com/netechsys/koha-plugin-cirriusimpact/issues)
- **Email**: tcr@cgstogo.com

---

## 📝 License

This plugin is licensed under the **GNU General Public License v3.0**.

See [LICENSE](LICENSE) for full details.

---

## 🙏 Credits

**Developed by:** netechsys / Terry Rossio  
**For:** CirriusImpact 
**Integration:** CirriusImpact Messaging API  
**Platform:** Koha ILS

---

## 📊 Project Stats

- **Version**: 1.1.16
- **Release Date**: October 14, 2025
- **Lines of Code**: 8,000+
- **Documentation Files**: 12+
- **Template Examples**: 35+
- **Test Coverage**: Comprehensive validation
- **Production Status**: ✅ Ready

---

## 🎯 Roadmap

### **Completed** ✅
- HOLD message support (digest)
- HOLDDGST message support (automatic digest grouping)
- CHECKOUT message support (digest)
- CHECKIN message support (digest)
- ODUE message support (single-item)
- PREDUE message support (digest)
- Automatic CSV field population
- ODUE suppression logic
- Multi-document YAML support
- Title extraction and matching
- Comprehensive documentation
- Message template installer
- Configurable messageText column
- Critical module assignment fixes

### **Future Enhancements** 🔮
- Additional notice types (RECALL, etc.)
- Custom field mappings
- Advanced reporting
- Web dashboard for monitoring
- Multi-language support enhancements

---

## ⭐ Show Your Support

If this plugin helps your library, please:
- ⭐ **Star this repository** on GitHub
- 🐛 **Report bugs** via [GitHub Issues](https://github.com/netechsys/koha-plugin-cirriusimpact/issues)
- 💡 **Suggest features** via [GitHub Discussions](https://github.com/netechsys/koha-plugin-cirriusimpact/discussions)
- 📢 **Share** with other Koha libraries

---

## 🚀 Quick Links

- 📥 [Download Latest Release](https://github.com/netechsys/koha-plugin-cirriusimpact/releases/latest)
- 📖 [Read Documentation](CirriusImpact/)
- 🐛 [Report Issues](https://github.com/netechsys/koha-plugin-cirriusimpact/issues)
- 📝 [View Changelog](CirriusImpact/CHANGELOG.md)
- ✅ [Test Results](CirriusImpact/TESTING_RESULTS_v1.1.9.md)

---

<div align="center">

**Made with ❤️ for the Koha Community**

[Koha Community](https://koha-community.org/) | [ByWater Solutions](https://bywatersolutions.com/) | [CirriusImpact](https://cirriusimpact.com/)

</div>