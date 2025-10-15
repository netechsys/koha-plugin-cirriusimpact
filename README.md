# CirriusImpact Koha Plugin

[![Version](https://img.shields.io/badge/version-1.1.25-blue.svg)](https://github.com/netechsys/koha-plugin-cirriusimpact/releases/tag/v1.1.25)
[![License](https://img.shields.io/badge/license-GPL--3.0-green.svg)](LICENSE)
[![Koha](https://img.shields.io/badge/Koha-Compatible-orange.svg)](https://koha-community.org/)

**Production-ready Koha plugin for automated patron messaging via SMS, Phone Calls, Email, and WhatsApp with CSV export to CirriusImpact API.**

---

## 📋 Table of Contents

- [Features](#features)
- [What's New in v1.1.9](#whats-new-in-v119)
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
- **CHECKOUT** - Item checkout confirmations (digest)
- **CHECKIN** - Item return confirmations (digest) 🆕
- **ODUE/ODUE2/ODUE3** - Overdue reminders (single-item)

### 🔄 **Intelligent Processing**
- **Digest Support** - Combine multiple items into single messages
- **Individual Messages** - Send separate messages per item
- **Patron Preferences** - Respects patron messaging preferences
- **ODUE Suppression** - Skip phone ODUE if patron has SMS/Email enabled
- **Auto-Population** - Automatically fills CSV fields (itemsID, title, date, etc.)

### 📊 **CSV Export**
- **26 Complete Fields** - All required data for CirriusImpact API
- **Automatic Backfilling** - Enriches message data with item details
- **Title Matching** - Extracts and matches titles from messages
- **SFTP Upload** - Automated transfer to CirriusImpact
- **Validated Output** - 546 data points tested across 21 messages

---

## 🆕 What's New in v1.1.9

### **CHECKIN Message Support**
✅ New `_ci_backfill_checkin_identifiers()` function  
✅ Auto-populates: `itemsID`, `biblionumber`, `title`, `date` (returndate)  
✅ Title extraction from rendered messages  
✅ Database matching to `old_issues` table (24-hour window)  
✅ Works for all transports: SMS, Phone, Email, WhatsApp

### **ODUE Template Fix**
✅ Simplified ODUE templates to avoid Koha TT `.size` method errors  
✅ Single-item format (one message per overdue item)  
✅ Updated ODUE, ODUE2, ODUE3 templates  
✅ Phone suppression working correctly when patron has SMS enabled

### **Documentation Updates**
✅ Updated `QUICKSTART.md` with CHECKIN + simplified ODUE templates  
✅ Updated `NOTICE_EXAMPLES.md` with 6 CHECKIN options  
✅ Added comprehensive `TESTING_RESULTS_v1.1.9.md`  
✅ Updated `CHANGELOG.md` with all v1.1.9 changes

### **Complete Testing**
✅ **21 messages tested** across 4 notice types  
✅ **HOLD**: 4 messages ✓  
✅ **CHECKOUT**: 4 messages ✓  
✅ **CHECKIN**: 4 messages ✓  
✅ **ODUE**: 9 messages ✓  
✅ **All CSV fields validated** (546 data points)

---

## 🚀 Quick Start

### **Installation** (5 minutes)

```bash
# 1. Download the plugin
wget https://github.com/netechsys/koha-plugin-cirriusimpact/archive/refs/tags/v1.1.9.zip

# 2. Install in Koha
# Upload via: Administration → Plugins → Upload plugin

# 3. Install SMS drivers
cd /var/lib/koha/[INSTANCE]/plugins/Koha/Plugin/Com/ByWaterSolutions/CirriusImpact/
perl install_sms_driver.pl

# 4. Configure Koha
# Set: SMSSendDriver = 'US::CirriusImpact'
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
4. Click **Save Configuration**

### **Add Notice Templates** (2 minutes)

Copy templates from [`QUICKSTART.md`](CirriusImpact/QUICKSTART.md) into:
- **Tools → Notices & Slips**
- Create separate notices for SMS and Phone transports

**Example SMS HOLD Template:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
holds: [% holds_list %]
sms:
  text: "[% branch.branchcode %]: [% IF holds.size > 1 %][% holds.size %] holds ready: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %]; [% END %][% END %][% ELSE %]Hold ready: [% biblio.title %][% END %]. Pickup by [% holds.0.expirationdate || hold.expirationdate | $KohaDates %]"
---
```

**Ready to test!** 🎉

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

### **CHECKOUT Notices** (Digest Format)
- **Multiple checkouts** combined into one message
- **Due dates** shown for all items
- **Automatic itemsID population** via backfill
- **Example**: "Checked out 3 items: Learning SQL; The poems; The bible. All due 10/25/2025"

### **CHECKIN Notices** (Digest Format) 🆕
- **Multiple check-ins** combined into one message
- **Return confirmation** for patron peace of mind
- **Automatic field population** (itemsID, title, date)
- **Example**: "The following items have been checked in: Learning SQL; The poems. Thank you."

### **ODUE Notices** (Single-Item Format)
- **One message per overdue item** (not digest)
- **Escalation levels**: ODUE, ODUE2, ODUE3
- **Smart suppression**: Skip phone if patron has SMS
- **Example**: "CPL OVERDUE: Learning SQL due 10/05/2025. Return now!"

---

## ✅ Testing & Validation

### **Production Tested**
- ✅ **21 messages** processed successfully
- ✅ **4 notice types** (HOLD, CHECKOUT, CHECKIN, ODUE)
- ✅ **2 transports** (SMS + Phone)
- ✅ **26 CSV fields** validated
- ✅ **546 data points** verified

### **Test Results**

| Notice Type | Messages | Patrons | Status |
|-------------|----------|---------|--------|
| HOLD | 4 | 2 | ✅ Perfect |
| CHECKOUT | 4 | 2 | ✅ Perfect |
| CHECKIN | 4 | 2 | ✅ Perfect |
| ODUE | 9 | 1 | ✅ Perfect |
| **Total** | **21** | **2** | ✅ **Production Ready** |

### **CSV Field Validation**
All 26 fields verified:
- ✅ `commType`, `language`, `notificationType`, `notificationLevel`
- ✅ `patronBarCode`, `patronFirstName`, `patronLastName`, `phone`, `email`
- ✅ `branch`, `branchname`
- ✅ `itemsID`, `biblionumber`, `title`, `date`
- ✅ `DeliveryOptionID`, `LanguageID`, `NotificationTypeID`, `ReportingOrgID`
- ✅ `PatronID`, `ItemRecordID`, `RequestID`, `TxnID`
- ✅ `PickupAreaDescription`, `AccountBalance`
- ✅ `messageText` (SMS text or Phone script)

See [TESTING_RESULTS_v1.1.9.md](CirriusImpact/TESTING_RESULTS_v1.1.9.md) for complete details.

---

## 📥 Download

### **Latest Release: v1.1.9**

**Direct Download:**
- **GitHub Release**: [v1.1.9](https://github.com/netechsys/koha-plugin-cirriusimpact/releases/tag/v1.1.9)
- **Archive**: [Download ZIP](https://github.com/netechsys/koha-plugin-cirriusimpact/archive/refs/tags/v1.1.9.zip)

**What's Included:**
- 1 main plugin file (`CirriusImpact.pm` v1.1.9)
- 2 SMS drivers (US::CirriusImpact, CirriusImpact)
- 12 documentation files
- 2 installation scripts
- 1 configuration template

**Package Size:** 81KB  
**Files:** 28 total  
**Release Date:** October 12, 2025

---

## 🔧 System Requirements

- **Koha Version**: 20.05 or later (tested on 23.x)
- **Perl**: 5.26 or later
- **Dependencies**: 
  - `Net::SFTP::Foreign` (for SFTP upload)
  - `YAML::XS` (for template parsing)
  - `SMS::Send` (for SMS functionality)
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

---

## 🤝 Support

### **Documentation**
- **Quick Start**: [QUICKSTART.md](CirriusImpact/QUICKSTART.md)
- **Examples**: [NOTICE_EXAMPLES.md](CirriusImpact/NOTICE_EXAMPLES.md)
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

- **Version**: 1.1.9
- **Release Date**: October 12, 2025
- **Lines of Code**: 7,812
- **Documentation Files**: 12
- **Template Examples**: 35+
- **Test Coverage**: 21 messages validated
- **Production Status**: ✅ Ready

---

## 🎯 Roadmap

### **Completed** ✅
- HOLD message support (digest)
- CHECKOUT message support (digest)
- CHECKIN message support (digest) 🆕
- ODUE message support (single-item) 🆕
- Automatic CSV field population
- ODUE suppression logic
- Multi-document YAML support
- Title extraction and matching
- Comprehensive documentation

### **Future Enhancements** 🔮
- Additional notice types (PRE-DUE, RECALL, etc.)
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

