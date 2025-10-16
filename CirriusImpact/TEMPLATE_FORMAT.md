# CirriusImpact Template Format Reference

## Important: SMS and Phone are Separate Notices

In Koha, you create **separate notices** for SMS and Phone transports. Each notice contains only one transport type.

---

## SMS Notice Template Format

Paste this into your **SMS transport notice**:

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
holds: [% holds_list %]
sms:
  text: "Your SMS message text here"
---
```

**Result:**
- `commType` = `S` (SMS)
- `messageText` column = value from `sms:text`

---

## Phone Notice Template Format

Paste this into your **Phone transport notice**:

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
holds: [% holds_list %]
call:
  script: "Your phone script text here"
---
```

**Result:**
- `commType` = `V` (Voice/Phone)
- `messageText` column = value from `call:script`

---

## CSV Output: messageText Column (26th column)

The `messageText` column (added at the end of the CSV) contains:

| Transport Type | messageText Source | commType |
|----------------|-------------------|----------|
| SMS            | `sms:text`        | S        |
| Phone          | `call:script`     | V        |
| Email          | `email:body`      | E        |
| WhatsApp       | `whatsapp:text`   | W        |

---

## Complete Example: HOLD Notice

### SMS Version
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
holds: [% holds_list %]
sms:
  text: "[% branch.branchcode %]: [% IF holds.size > 1 %][% holds.size %] holds ready: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %]; [% END %][% END %][% ELSE %]Hold ready: [% biblio.title %][% END %]. Pickup by [% holds.0.expirationdate || hold.expirationdate | $KohaDates %]"
---
```

**CSV Output:**
```csv
S,default,HOLD,...,52,...,"CPL: 3 holds ready: Learning SQL; The poems; The bible. Pickup by 10/18/2025"
```

### Phone Version
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
holds: [% holds_list %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. [% IF holds.size > 1 %][% holds.size %] items ready: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %], [% END %][% END %][% ELSE %]One item ready: [% biblio.title %][% END %]. Pickup by [% holds.0.expirationdate || hold.expirationdate | $KohaDates %]. Call [% branch.branchphone %]."
---
```

**CSV Output:**
```csv
V,default,HOLD,...,52,...,"Hello Yossi. Centerville. 3 items ready: Learning SQL, The poems, The bible. Pickup by 10/18/2025. Call 555-1234."
```

---

## Key Points

1. **Separate Notices**: SMS and Phone are **separate notice templates** in Koha
2. **One Transport Per Notice**: Each notice has only `sms:` OR `call:`, never both
3. **messageText Column**: Automatically populated based on transport type
4. **Digest Support**: Templates work for both digest and individual patron preferences
5. **Universal Templates**: Use `[% IF items.size > 1 %]` to handle both modes

---

## Where to Find More Examples

- **Quick Templates**: `NOTICE_EXAMPLES.md` (top section)
- **Digest Guide**: `DIGEST_VS_INDIVIDUAL.md`
- **Quick Reference**: `DIGEST_QUICK_REFERENCE.md`
- **Full Documentation**: `README.md` and `INSTALL.md`

---

**Version:** 1.1.7  
**Updated:** October 11, 2025





