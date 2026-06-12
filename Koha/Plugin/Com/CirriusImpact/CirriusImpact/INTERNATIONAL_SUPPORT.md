# International Phone Number Support

## Overview

The CirriusImpact SMS::Send driver is an **international-class driver** that supports phone numbers from any country in any format.

## Driver Classification

### International vs Regional Drivers

SMS::Send supports two types of drivers:

1. **International Drivers** (e.g., `SMS::Send::CirriusImpact`)
   - Named without country code
   - Accept phone numbers in ANY format
   - Work with international prefixes (+1, +44, +61, etc.)
   - Work with regional/local formats

2. **Regional Drivers** (e.g., `SMS::Send::US::Something`)
   - Named with country code (US, UK, AU, etc.)
   - Typically only accept local formats for that region
   - May require specific formatting

**CirriusImpact uses an international driver:** `SMS::Send::CirriusImpact`

## Supported Phone Number Formats

The driver accepts **all** phone number formats and passes them through to the CirriusImpact service without validation:

### International Formats
```
✓ +1 555 123 4567        (United States)
✓ +44 20 1234 5678       (United Kingdom)
✓ +61 2 1234 5678        (Australia)
✓ +33 1 23 45 67 89      (France)
✓ +49 30 12345678        (Germany)
✓ +81 3-1234-5678        (Japan)
✓ +86 10 1234 5678       (China)
✓ +91 11 1234 5678       (India)
```

### Regional/Local Formats
```
✓ (555) 010-0000         (US local format)
✓ 555-0100           (US dashed format)
✓ 555-0100             (Plain digits)
✓ 020 1234 5678          (UK local format)
✓ 02 1234 5678           (AU local format)
```

### Mixed Formats in Database
The driver works with whatever format is stored in:
- Koha patron `smsalertnumber` field
- Koha patron `phone` field
- Custom number provided in notice templates

## How It Works

1. **Koha** stores patron phone numbers in `smsalertnumber` or `phone` fields
2. **Message queue** generates notice with phone number
3. **SMS::Send::CirriusImpact driver** receives the number
4. **No validation** - driver passes number as-is to plugin
5. **CirriusImpact plugin** includes number in CSV export
6. **CirriusImpact service** handles actual number validation and delivery

## Configuration Recommendations

### For International Libraries

1. **Store numbers in international format** in Koha:
   ```
   Patron record:
   SMS Number: +44 20 1234 5678  (recommended)
   ```

2. **Train staff** to enter numbers with country codes:
   - Use leading + and country code
   - Example: +44 for UK, +1 for US, +61 for AU

3. **Update patron records** to standardize format:
   - Migrate existing numbers to international format
   - Add country code if missing

### For Single-Country Libraries

You can use either format:

**Option 1: International format (recommended)**
```
+1 555 123 4567
```

**Option 2: Local format**
```
(555) 010-0000
555-0100
```

## Testing International Numbers

Test with various formats:

```perl
# Test script
use SMS::Send;

my $sender = SMS::Send->new('CirriusImpact');

# US number
$sender->send_sms(
    to => '+1 555 123 4567',
    text => 'US test'
);

# UK number  
$sender->send_sms(
    to => '+44 20 1234 5678',
    text => 'UK test'
);

# Australian number
$sender->send_sms(
    to => '+61 2 1234 5678',
    text => 'AU test'
);
```

## CirriusImpact Service Support

The driver passes all numbers to CirriusImpact's service. Check with CirriusImpact regarding:

- Which countries they support for SMS delivery
- Which countries they support for voice calls
- Number format requirements for their service
- International pricing/rates

## Troubleshooting

### Numbers Not Delivering

If messages aren't delivering:

1. **Check format in Koha**: View patron record, verify number format
2. **Check CSV export**: Look in archive directory, verify number in CSV
3. **Check CirriusImpact logs**: Verify service accepts the format
4. **Standardize format**: Convert all numbers to international format with +

### Format Recommendations

| Country | Recommended Format | Example |
|---------|-------------------|---------|
| United States | +1 XXX XXX XXXX | +1 555 123 4567 |
| United Kingdom | +44 XX XXXX XXXX | +44 20 1234 5678 |
| Australia | +61 X XXXX XXXX | +61 2 1234 5678 |
| Canada | +1 XXX XXX XXXX | +1 416 555 1234 |
| France | +33 X XX XX XX XX | +33 1 23 45 67 89 |
| Germany | +49 XXX XXXXXXXX | +49 30 12345678 |

### Migration Script

To standardize existing patron numbers:

```sql
-- Example: Add +1 to US numbers without country code
-- Review and test before running!

UPDATE borrowers 
SET smsalertnumber = CONCAT('+1', smsalertnumber)
WHERE smsalertnumber IS NOT NULL 
  AND smsalertnumber NOT LIKE '+%'
  AND LENGTH(REGEXP_REPLACE(smsalertnumber, '[^0-9]', '')) = 10;
```

## Summary

✅ **Supports ALL phone number formats**
✅ **International-class driver** (not US-specific)
✅ **No format validation** - accepts any format
✅ **Works worldwide** - US, UK, AU, and other countries
✅ **Flexible** - supports both international and regional formats

The actual delivery capability depends on CirriusImpact's service coverage. Contact CirriusImpact for details on supported countries and regions.

---

**Version:** 1.0.1  
**Updated:** October 11, 2025  
**Plugin Version: 1.1.9
