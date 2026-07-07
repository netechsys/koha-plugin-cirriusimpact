# Dual Driver Support - CirriusImpact

## Overview

The CirriusImpact plugin now supports **TWO SMS::Send drivers** to provide maximum flexibility and backward compatibility:

1. **SMS::Send::US::CirriusImpact** - Regional + International (Recommended)
2. **SMS::Send::CirriusImpact** - International only (Legacy/Compatibility)

Both drivers are installed automatically by `install_sms_driver.pl`.

## Why Two Drivers?

### The Challenge
SMS::Send framework treats drivers differently based on naming:
- **International drivers** (SMS::Send::Name) require phone numbers with + prefix
- **Regional drivers** (SMS::Send::XX::Name) accept local formats without +

### The Solution
Install both drivers to support all scenarios:
- Libraries using regional US numbers (555-0100)
- Libraries using international numbers (+44 20 1234 5678)
- Mixed environments
- Legacy installations

## Driver Comparison

| Feature | US::CirriusImpact | CirriusImpact |
|---------|-------------------|---------------|
| **Classification** | US Regional | International |
| **US Regional** | ✅ 555-0100 | ❌ Requires +1 |
| **US International** | ✅ +1 555 0100 | ✅ +1 555 0100 |
| **UK Numbers** | ✅ +44 20 1234 5678 | ✅ +44 20 1234 5678 |
| **Other International** | ✅ +XX ... | ✅ +XX ... |
| **Recommended For** | Most users | Int'l only |

## Which Driver Should You Use?

### Use US::CirriusImpact if:
- ✅ You have US patrons with regional numbers (no + prefix)
- ✅ You want flexibility (regional OR international)
- ✅ You're starting fresh
- ✅ You want to avoid phone number validation errors

**Configuration:**
```
SMSSendDriver = 'US::CirriusImpact'
```

### Use CirriusImpact if:
- ✅ All your phone numbers have + prefix
- ✅ You're upgrading from an older version
- ✅ You prefer strict international format
- ✅ Your existing configuration uses 'CirriusImpact'

**Configuration:**
```
SMSSendDriver = 'CirriusImpact'
```

## Installation

The `install_sms_driver.pl` script automatically installs **BOTH** drivers:

```bash
sudo perl install_sms_driver.pl
```

This installs:
1. `/usr/share/perl5/SMS/Send/US/CirriusImpact.pm`
2. `/usr/share/perl5/SMS/Send/CirriusImpact.pm`

No additional steps needed!

## Configuration

After installation, choose your driver in Koha:

**Administration > Global System Preferences > Patrons**

**Recommended:**
```
SMSSendDriver = 'US::CirriusImpact'
```

**Alternative (legacy):**
```
SMSSendDriver = 'CirriusImpact'
```

## Verification

Check which drivers are installed:

```bash
# Check US driver
perl -MSMS::Send::US::CirriusImpact -e 'print "US driver OK\n"'

# Check international driver
perl -MSMS::Send::CirriusImpact -e 'print "International driver OK\n"'
```

Or run the verification script:

```bash
perl verify_installation.pl
```

Expected output:
```
✓ SMS::Send::US::CirriusImpact driver is installed (current)
✓ SMS::Send::CirriusImpact driver is installed (legacy)
```

## Phone Number Format Examples

### With US::CirriusImpact (Recommended)

All of these work:
```
✓ 555-0100                (US regional)
✓ 555-0100           (US formatted)
✓ 555-0100             (US dashed)
✓ +1 555 0100          (US international)
✓ +44 20 1234 5678         (UK)
✓ +61 2 1234 5678          (Australia)
✓ +33 1 23 45 67 89        (France)
```

### With CirriusImpact (International)

Only these work:
```
✓ +1 732 586 1275          (US international)
✓ +44 20 1234 5678         (UK)
✓ +61 2 1234 5678          (Australia)
✗ 555-0100               (Error: requires +)
✗ 555-0100           (Error: requires +)
```

## Migration Guide

### Upgrading from v1.1.6 or Earlier

If you previously had `SMSSendDriver = 'CirriusImpact'`:

**Option 1: Keep existing (works fine)**
```bash
# No changes needed
# Your configuration continues to work
# Phone numbers must have + prefix
```

**Option 2: Upgrade to US:: (recommended)**
```bash
# 1. Install both drivers (done by install_sms_driver.pl)
# 2. Update preference:
#    Administration > System Preferences > Patrons
#    SMSSendDriver = 'US::CirriusImpact'
# 3. Benefit: Regional numbers now work without +
```

### New Installations

Fresh installations should use:
```
SMSSendDriver = 'US::CirriusImpact'
```

This provides maximum flexibility.

## Troubleshooting

### Error: "SMS::Send driver CirriusImpact does not exist"

**Solution:** Install the drivers:
```bash
sudo perl install_sms_driver.pl
```

### Error: "Cannot use regional phone numbers with an international driver"

**Cause:** Using `SMSSendDriver = 'CirriusImpact'` with regional numbers

**Solution:** Change to US driver:
```
SMSSendDriver = 'US::CirriusImpact'
```

### Verification shows warning about US driver

**Message:** "US::CirriusImpact driver not found (recommended...)"

**Solution:** Re-run installer:
```bash
sudo perl install_sms_driver.pl
```

It will install both drivers.

## Technical Details

### Driver Implementation

Both drivers extend `SMS::Send::Driver` and implement:
- `new()` - Constructor
- `send_sms()` - Send method (returns success to queue message)

**US::CirriusImpact** additionally:
- Accepts any phone number format (no validation)
- Works as US regional driver (no + required for US numbers)
- Passes through international numbers unchanged

**CirriusImpact** additionally:
- Has `sends_to_anyone()` method (returns 1)
- But SMS::Send still enforces + prefix for international drivers
- Best for strictly international deployments

### Why Both?

- **Backward Compatibility**: Existing installs don't break
- **Flexibility**: Choose based on your phone number format
- **Future-Proof**: Can switch between drivers anytime
- **No Data Migration**: Just change preference

## Recommendations

### For US Libraries
```
✓ Use: US::CirriusImpact
✓ Benefit: No + prefix needed
✓ Works with: 555-0100, +1 555 0100, +44...
```

### For International Libraries
```
✓ Use: US::CirriusImpact (still works!)
✓ or: CirriusImpact (if you prefer strict + format)
✓ Works with: +44 20 1234 5678, +61 2 1234 5678
```

### For Mixed Environments
```
✓ Use: US::CirriusImpact
✓ Handles: Both regional and international
✓ No phone number reformatting needed
```

## Summary

✅ **Install both drivers** - Done automatically by `install_sms_driver.pl`  
✅ **Choose your preference** - US::CirriusImpact (recommended) or CirriusImpact (legacy)  
✅ **Backward compatible** - Existing configurations continue working  
✅ **Flexible** - Switch anytime by changing SMSSendDriver preference  

**Recommended for all users:** `SMSSendDriver = 'US::CirriusImpact'`

---

**Version:** 1.1.9  
**Last Updated:** October 11, 2025  
**Author: Example User, CirriusImpact






