# CirriusImpact Notice Template Examples

This document provides complete, ready-to-use notice template examples for various scenarios.

**🆕 NEW in v1.1.9:** 
- CSV now includes `messageText` column with full message content
- Universal templates that work for BOTH digest and individual modes
- Every example includes SMS **and** Phone templates side-by-side

## Important: Separate Notice Definitions

**SMS, Phone, Email, and WhatsApp are SEPARATE notice definitions in Koha.**

- **SMS Transport**: Uses `sms:` section (WhatsApp also uses `sms:`)
- **Phone Transport**: Uses `call:` section  
- **Email Transport**: Uses `email:` section

**Do NOT combine multiple transports in one YAML.** Create separate notice templates for each transport type in Koha's notice editor.

## Important: Digest vs Individual

**Patrons choose in their messaging preferences:**
- ☑ **Digest only** → Koha sends 1 message with all items → 1 CSV row
- ☐ **Not checked** → Koha sends 1 message per item → Multiple CSV rows

**Our templates use `[% IF items.size > 1 %]` to automatically adapt!**

See `DIGEST_VS_INDIVIDUAL.md` for complete explanation.

## Table of Contents

1. [Quick Copy-Paste Templates (SMS + Phone)](#quick-copy-paste-templates)
2. [CHECKOUT Notices](#checkout-notices)
3. [HOLD Notices](#hold-notices)
4. [ODUE Notices](#odue-notices)
5. [CHECKIN Notices](#checkin-notices)
6. [Multi-Transport Examples](#multi-transport-examples)

---

## Quick Copy-Paste Templates

### Universal HOLD (Works for Digest AND Individual)

**SMS Version:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
holds: [% holds_list %]
sms:
  text: "[% branch.branchcode %]: [% IF holds.size > 1 %][% holds.size %] holds ready: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %]; [% END %][% END %][% ELSE %]Hold ready: [% biblio.title %][% END %]. Pickup by [% holds.0.expirationdate || hold.expirationdate | $KohaDates %]"
---
```

**Phone Version:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
holds: [% holds_list %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. [% IF holds.size > 1 %][% holds.size %] items ready: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %], [% END %][% END %][% ELSE %]One item ready: [% biblio.title %][% END %]. Pickup by [% holds.0.expirationdate || hold.expirationdate | $KohaDates %]. Call [% branch.branchphone %]."
---
```

**CSV messageText column:** For SMS, contains the `text:` value. For Phone, contains the `script:` value.

**Output if patron has Digest enabled (3 items):**
- SMS: `"CPL: 3 holds ready: Learning SQL; The poems; The bible. Pickup by 10/18/2025"`
- Phone: `"Hello Yossi. Centerville. 3 items ready: Learning SQL, The poems, The bible. Pickup by..."`
- CSV: **1 row**

**Output if patron has Digest disabled (3 items):**
- SMS: `"CPL: Hold ready: Learning SQL. Pickup by 10/18/2025"` (×3 messages)
- CSV: **3 rows** (one per item)

### Universal CHECKOUT (Works for Digest AND Individual)

**SMS Version:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: [% IF checkouts.size > 1 %]Checked out [% checkouts.size %] items: [% FOREACH c IN checkouts %][% c.item.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]. All due [% checkouts.0.date_due | $KohaDates %][% ELSE %]Checked out: [% biblio.title %]. Due [% checkout.date_due | $KohaDates %][% END %]"
---
```

**Phone Version:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. [% IF checkouts.size > 1 %]You checked out [% checkouts.size %] items: [% FOREACH c IN checkouts %][% c.item.biblio.title %][% UNLESS loop.last %], [% END %][% END %]. All due [% checkouts.0.date_due | $KohaDates %][% ELSE %]You checked out [% biblio.title %] due [% checkout.date_due | $KohaDates %][% END %]. Thank you!"
---
```

### Universal ODUE (Single-Item Format)

**SMS Version:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %] OVERDUE: [% biblio.title %] due [% issue.date_due | $KohaDates %]. Return now!"
---
```

**Phone Version:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Overdue: [% biblio.title %] due [% issue.date_due | $KohaDates %]. Return immediately. [% branch.branchphone %]."
---
```

**Note:** ODUE templates use single-item format. Koha generates **one message per overdue item**, not digest. Use ODUE, ODUE2, ODUE3 letter codes for escalation levels.

### Universal CHECKIN (Works for Digest AND Individual)

**SMS Version:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: The following items have been checked in: [% IF checkins.size > 1 %][% FOREACH c IN checkins %][% c.biblio.title %][% UNLESS loop.last %]; [% END %][% END %][% ELSE %][% biblio.title %][% END %]. Thank you."
---
```

**Phone Version:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. The following item was checked in: [% IF checkins.size > 1 %][% FOREACH c IN checkins %][% c.biblio.title %][% UNLESS loop.last %], [% END %][% END %][% ELSE %][% biblio.title %][% END %]. Thank you!"
---
```

**CSV Output:** 
- ✅ `itemsID`: Auto-populated from database
- ✅ `title`: Extracted from message and matched to check-in
- ✅ `date`: Populated with return date
- ✅ `messageText`: Contains SMS `text:` or Phone `script:` content

**Important:** Phone messages use the `call:script` field, which is automatically written to the `messageText` column in the CSV export.

---

---

## CHECKOUT Notices

### Option 1: Single Item per Message (Default)

This creates one message per checkout. Good for immediate notifications per item.

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "You checked out '[% biblio.title %]' from [% branch.branchname %]. Due: [% checkout.date_due | $KohaDates %]. Questions? Call [% branch.branchphone %]"
---
```

**Result:** If patron checks out 3 books, they get 3 separate messages.

---

### Option 2: Digest - All Items in One Message (Recommended)

This combines all items checked out in one session into a single message.

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchname %] - Items checked out: [% FOREACH checkout IN checkouts %][% checkout.item.biblio.title %] (due [% checkout.date_due | $KohaDates %])[% UNLESS loop.last %]; [% END %][% END %]. Questions? Call [% branch.branchphone %]"
---
```

**Result:** Patron checks out 3 books → 1 message listing all 3 titles.

**Example output:**
```
Centerville - Items checked out: Learning SQL (due 10/25/2025); The poems (due 10/25/2025); The bible (due 10/25/2025). Questions? Call 7315551234
```

---

### Option 3: Digest - Formatted List with Bullet Points

This creates a nicely formatted list of all items.

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: |
    [% branch.branchname %] - You checked out [% checkouts.size %] item(s):
    [% FOREACH checkout IN checkouts %]
    • [% checkout.item.biblio.title %] - Due: [% checkout.date_due | $KohaDates %]
    [% END %]
    Return on time to avoid fines. Questions? [% branch.branchphone %]
---
```

**Example output:**
```
Centerville - You checked out 3 item(s):
• Learning SQL - Due: 10/25/2025
• The poems - Due: 10/25/2025
• The bible - Due: 10/25/2025
Return on time to avoid fines. Questions? 7315551234
```

---

### Option 4: Digest - Numbered List

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "Thanks for visiting [% branch.branchname %]! You checked out: [% FOREACH checkout IN checkouts %][% loop.count %]. [% checkout.item.biblio.title %][% UNLESS loop.last %], [% END %][% END %]. All due [% checkouts.0.date_due | $KohaDates %]. Enjoy!"
---
```

**Example output:**
```
Thanks for visiting Centerville! You checked out: 1. Learning SQL, 2. The poems, 3. The bible. All due 10/25/2025. Enjoy!
```

---

### Option 5: Compact Digest (for long lists)

When patrons check out many items, keep it brief:

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: |
    [% branch.branchname %]: Checked out [% checkouts.size %] item(s).
    [% IF checkouts.size <= 3 %]
    [% FOREACH checkout IN checkouts %]• [% checkout.item.biblio.title %]
    [% END %]
    [% ELSE %]
    First 3: [% checkouts.0.item.biblio.title %]; [% checkouts.1.item.biblio.title %]; [% checkouts.2.item.biblio.title %]...
    [% END %]
    All due [% checkouts.0.date_due | $KohaDates %]. Check your account for full list.
---
```

---

## HOLD Notices

### Option 1: Single Hold (One Message per Hold)

Creates separate messages for each hold. Good for immediate notifications.

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
hold: [% hold.reserve_id %]
sms:
  text: "[% branch.branchname %] - Hold ready: [% biblio.title %]. Pickup at [% branch.branchname %]. Hold until [% hold.expirationdate | $KohaDates %]. Questions? Call [% branch.branchphone %]"
---
```

**Result:** If patron has 3 holds ready, they get 3 separate messages.

---

### Option 2: Digest - All Holds in One Message (Recommended)

Combines all ready holds into a single message.

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
holds: [% holds_list %]
sms:
  text: "[% branch.branchname %] - [% holds.size %] hold(s) ready: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]. Pickup at [% branch.branchname %]. Questions? [% branch.branchphone %]"
---
```

**Example output:**
```
Centerville - 3 hold(s) ready: Learning SQL; The poems; The bible. Pickup at Centerville. Questions? 7315551234
```

---

### Option 3: Digest - Formatted List with Bullet Points

Creates a nicely formatted list for easier reading.

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
holds: [% holds_list %]
sms:
  text: |
    [% branch.branchname %] - [% holds.size %] hold(s) ready for pickup:
    [% FOREACH h IN holds %]
    • [% h.biblio.title %]
    [% END %]
    Pick up by [% holds.0.expirationdate | $KohaDates %]. Questions? [% branch.branchphone %]
---
```

**Example output:**
```
Centerville - 3 hold(s) ready for pickup:
• Learning SQL
• The poems
• The bible
Pick up by 10/18/2025. Questions? 7315551234
```

---

### Option 4: Digest - Numbered List

Shows items with numbers for easy reference.

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
holds: [% holds_list %]
sms:
  text: "[% branch.branchname %] - [% holds.size %] holds ready: [% FOREACH h IN holds %][% loop.count %]. [% h.biblio.title %][% UNLESS loop.last %] [% END %][% END %]. Pickup: [% branch.branchname %]"
---
```

**Example output:**
```
Centerville - 3 holds ready: 1. Learning SQL 2. The poems 3. The bible. Pickup: Centerville
```

---

### Option 5: Digest with Expiration Dates

Shows when each hold expires.

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
holds: [% holds_list %]
sms:
  text: "[% branch.branchname %] holds ready: [% FOREACH h IN holds %][% h.biblio.title %] (expires [% h.expirationdate | $KohaDates %])[% UNLESS loop.last %]; [% END %][% END %]"
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. You have [% holds.size %] items ready for pickup: [% FOREACH h IN holds %][% h.biblio.title %] available until [% h.expirationdate | $KohaDates %]. [% END %] Please pick them up soon. For questions, call [% branch.branchphone %]."
---
```

---

### Option 6: Compact Digest (for many holds)

When patron has many holds, keep it brief:

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
holds: [% holds_list %]
sms:
  text: |
    [% branch.branchname %]: [% holds.size %] hold(s) ready!
    [% IF holds.size <= 3 %]
    [% FOREACH h IN holds %]• [% h.biblio.title %]
    [% END %]
    [% ELSE %]
    Including: [% holds.0.biblio.title %], [% holds.1.biblio.title %], [% holds.2.biblio.title %] + [% holds.size - 3 %] more
    [% END %]
    Pickup by [% holds.0.expirationdate | $KohaDates %]. [% branch.branchphone %]
---
```

---

## ODUE Notices (Overdue)

**Important:** ODUE notices work differently than CHECKOUT/HOLD/CHECKIN. Koha generates **one message per overdue item** (not digest), so templates should use **single-item format**.

### Option 1: Basic ODUE (Recommended)

Simple single-item format that works reliably.

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

**Result:** Each overdue item gets its own message. If patron has 3 overdues, they receive 3 messages.

---

### Option 2: With Fine Amount

Include the fine amount in the single-item message.

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %] OVERDUE: [% biblio.title %] due [% issue.date_due | $KohaDates %]. Fine: $[% item.fine %]. Return now!"
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Overdue: [% biblio.title %] due [% issue.date_due | $KohaDates %]. Current fine: $[% item.fine %]. Return immediately. [% branch.branchphone %]."
---
```

**Example output:**
```
SMS: "CPL OVERDUE: Learning SQL due 10/05/2025. Fine: $2.50. Return now!"
Phone: "Hello [% borrower.firstname %]. Centerville. Overdue: Learning SQL due 10/05/2025. Current fine: $2.50. Return immediately. 7315551234."
```

---

### Option 3: ODUE Level-Specific Messages

Use different messages for ODUE, ODUE2, and ODUE3 escalation levels.

**ODUE (First Notice):**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %] REMINDER: [% biblio.title %] due [% issue.date_due | $KohaDates %]. Please return soon."
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. Friendly reminder: [% biblio.title %] was due [% issue.date_due | $KohaDates %]. Please return it soon. [% branch.branchphone %]."
---
```

**ODUE2 (Second Notice - More Urgent):**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %] URGENT: [% biblio.title %] overdue since [% issue.date_due | $KohaDates %]. Fines accruing. Return NOW!"
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. URGENT: [% biblio.title %] is overdue since [% issue.date_due | $KohaDates %]. Fines are accruing daily. Return immediately. [% branch.branchphone %]."
---
```

**ODUE3 (Final Notice):**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %] FINAL NOTICE: [% biblio.title %] overdue. Account may be suspended. Return immediately!"
call:
  script: "This is a final notice from [% branch.branchname %]. [% biblio.title %] is seriously overdue. Your account will be suspended if not returned immediately. Please call [% branch.branchphone %]."
---
```

---

### Advanced ODUE Options (Digest Formats)

⚠️ **Warning:** The following digest-based ODUE examples use `overdues.size` which may cause Template Toolkit errors in some Koha versions. **Option 1 (single-item format) is recommended for production use.**

If you need digest functionality, these examples show the intended format, but you may need to test thoroughly in your Koha environment.

---

### Option 4: Digest - Numbered List with Days Overdue (Advanced)

Calculate and show how many days each item is overdue.

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchname %] OVERDUE: [% FOREACH o IN overdues %][% loop.count %]. [% o.item.biblio.title %] ([% o.days_overdue %] days late)[% UNLESS loop.last %] [% END %][% END %]. Return now!"
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. You have [% overdues.size %] overdue items. [% FOREACH o IN overdues %][% o.item.biblio.title %] is [% o.days_overdue %] days overdue. [% END %] Please return them immediately to avoid additional fines. For questions, call [% branch.branchphone %]."
---
```

**Example output:**
```
Centerville OVERDUE: 1. Learning SQL (6 days late) 2. The poems (3 days late) 3. The bible (10 days late). Return now!
```

---

### Option 5: Digest - First Notice with Fine Amount

Include the current fine amount in the message.

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchname %] - You have [% overdues.size %] overdue items. Current fines: $[% total_fines %]. Items: [% FOREACH o IN overdues %][% o.item.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]. Return to stop fines."
---
```

**Example output:**
```
Centerville - You have 3 overdue items. Current fines: $4.50. Items: Learning SQL; The poems; The bible. Return to stop fines.
```

---

### Option 6: Digest - Second/Third Notice (More Urgent)

Different message based on ODUE level.

**ODUE (First Notice):**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchname %] REMINDER: [% overdues.size %] overdue items: [% FOREACH o IN overdues %][% o.item.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]. Please return soon."
---
```

**ODUE2 (Second Notice):**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchname %] URGENT: [% overdues.size %] items still overdue: [% FOREACH o IN overdues %][% o.item.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]. Fines accruing daily. Return NOW."
---
```

**ODUE3 (Final Notice):**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchname %] FINAL NOTICE: [% overdues.size %] items overdue: [% FOREACH o IN overdues %][% o.item.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]. Account may be suspended. Return immediately!"
call:
  script: "This is a final notice from [% branch.branchname %] for [% borrower.firstname %] [% borrower.surname %]. You have [% overdues.size %] seriously overdue items. [% FOREACH o IN overdues %][% o.item.biblio.title %]. [% END %] Your account will be suspended if these items are not returned immediately. Please return them today or call [% branch.branchphone %] to discuss."
---
```

---

### Option 7: Digest - Compact Format (for many overdues)

When patron has many overdue items, show summary + first few.

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: |
    [% branch.branchname %] OVERDUE: [% overdues.size %] items
    [% IF overdues.size <= 3 %]
    [% FOREACH o IN overdues %]• [% o.item.biblio.title %]
    [% END %]
    [% ELSE %]
    Including: [% overdues.0.item.biblio.title %]; [% overdues.1.item.biblio.title %]; [% overdues.2.item.biblio.title %] + [% overdues.size - 3 %] more
    [% END %]
    Check account for details. Return ASAP!
---
```

**Example for 8 items:**
```
Centerville OVERDUE: 8 items
Including: Learning SQL; The poems; The bible + 5 more
Check account for details. Return ASAP!
```

---

### Option 8: Digest by Overdue Severity

Group items by how overdue they are.

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: |
    [% branch.branchname %] OVERDUE:
    [% SET recent = [] %]
    [% SET old = [] %]
    [% FOREACH o IN overdues %]
      [% IF o.days_overdue <= 7 %]
        [% recent.push(o) %]
      [% ELSE %]
        [% old.push(o) %]
      [% END %]
    [% END %]
    [% IF recent.size > 0 %]Recently overdue: [% FOREACH r IN recent %][% r.item.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]. [% END %]
    [% IF old.size > 0 %]Seriously overdue: [% FOREACH r IN old %][% r.item.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]. [% END %]
    Return all ASAP!
---
```

---

### Option 9: Digest with Pickup Location Info

For holds at different branches.

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
holds: [% holds_list %]
sms:
  text: |
    You have [% holds.size %] holds ready:
    [% FOREACH h IN holds %]
    • [% h.biblio.title %] @ [% h.branchcode %]
    [% END %]
    Expires [% holds.0.expirationdate | $KohaDates %]
---
```

**Example output (multi-branch):**
```
You have 3 holds ready:
• Learning SQL @ CPL
• The poems @ CPL  
• The bible @ MPL
Expires 10/18/2025
```

---

## CHECKIN Notices (Item Returned Confirmation)

### Option 1: Simple Confirmation - Single Item

Send a confirmation when one item is checked in.

**SMS Transport:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: [% biblio.title %] checked in. Thank you."
---
```

**Phone Transport:**
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Your item [% biblio.title %] has been checked in. Thank you!"
---
```

**Example output:**
```
SMS: "CPL: Learning SQL checked in. Thank you."
Phone: "Hello Terry. Centerville. Your item Learning SQL has been checked in. Thank you!"
```

---

### Option 2: Digest - Multiple Items

Confirm multiple check-ins in one message.

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
  script: "Hello [% borrower.firstname %]. The following items were checked in: [% IF checkins.size > 1 %][% FOREACH c IN checkins %][% c.biblio.title %][% UNLESS loop.last %], [% END %][% END %][% ELSE %][% biblio.title %][% END %]. Thank you!"
---
```

**Example output:**
```
SMS: "CPL: The following items have been checked in: Learning SQL; The poems; The bible. Thank you."
Phone: "Hello Terry. The following items were checked in: Learning SQL, The poems, The bible. Thank you!"
```

---

### Option 3: With Item Count

Show the number of items returned.

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchname %] - [% IF checkins.size > 1 %][% checkins.size %] items returned: [% FOREACH c IN checkins %][% c.biblio.title %][% UNLESS loop.last %]; [% END %][% END %][% ELSE %]1 item returned: [% biblio.title %][% END %]. Thank you!"
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. [% IF checkins.size > 1 %]We received [% checkins.size %] items from you: [% FOREACH c IN checkins %][% c.biblio.title %][% UNLESS loop.last %], [% END %][% END %][% ELSE %]We received [% biblio.title %] from you[% END %]. All set. Thank you!"
---
```

**Example output:**
```
SMS: "Centerville - 3 items returned: Learning SQL; The poems; The bible. Thank you!"
Phone: "Hello Terry. This is Centerville. We received 3 items from you: Learning SQL, The poems, The bible. All set. Thank you!"
```

---

### Option 4: Numbered List

List each returned item with a number.

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchname %] items returned: [% IF checkins.size > 1 %][% FOREACH c IN checkins %][% loop.count %]. [% c.biblio.title %][% UNLESS loop.last %] [% END %][% END %][% ELSE %][% biblio.title %][% END %]. All clear!"
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Items returned: [% IF checkins.size > 1 %][% FOREACH c IN checkins %][% loop.count %], [% c.biblio.title %]. [% END %][% ELSE %][% biblio.title %][% END %]. Thank you!"
---
```

**Example output:**
```
SMS: "Centerville items returned: 1. Learning SQL 2. The poems 3. The bible. All clear!"
Phone: "Hello Terry. Centerville. Items returned: 1, Learning SQL. 2, The poems. 3, The bible. Thank you!"
```

---

### Option 5: With Remaining Checkouts

Remind patron of items still checked out.

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Returned [% biblio.title %]. [% IF checkouts.size > 0 %]You still have [% checkouts.size %] items checked out.[% END %]"
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Your item [% biblio.title %] has been returned. [% IF checkouts.size > 0 %]You still have [% checkouts.size %] items checked out. [% END %]Thank you!"
---
```

**Example output (when patron has 2 items still out):**
```
SMS: "CPL: Returned Learning SQL. You still have 2 items checked out."
Phone: "Hello Terry. Centerville. Your item Learning SQL has been returned. You still have 2 items checked out. Thank you!"
```

---

### Option 6: With Fines/Fees Information

Include account balance if applicable.

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchname %] - Returned: [% biblio.title %]. [% IF borrower.account.balance > 0 %]Account balance: $[% borrower.account.balance %].[% END %] Thank you."
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. Your item [% biblio.title %] has been checked in. [% IF borrower.account.balance > 0 %]Your account balance is $[% borrower.account.balance %]. Please pay at your convenience.[% END %] Thank you!"
---
```

**Example output (with $4.50 balance):**
```
SMS: "Centerville - Returned: Learning SQL. Account balance: $4.50. Thank you."
Phone: "Hello Terry. This is Centerville. Your item Learning SQL has been checked in. Your account balance is $4.50. Please pay at your convenience. Thank you!"
```

---

### Important Notes for CHECKIN Notices

**Automatic Data Population (v1.1.9+):**
- ✅ `itemsID`: Automatically populated from database
- ✅ `biblionumber`: Automatically populated from database  
- ✅ `title`: Extracted from rendered message and matched to recent check-ins
- ✅ `date`: Populated with return date (returndate)

**How It Works:**
1. Plugin extracts title from your rendered script/text using regex
2. Queries `old_issues` table for check-ins in last 24 hours
3. Matches extracted title to database record
4. Populates CSV fields with accurate data

**Title Extraction Pattern:**
The plugin looks for: `"checked in: [TITLE]. Thank you"`

Make sure your message includes this pattern for automatic matching to work correctly.

---

## Multi-Transport Examples

### Send Same Message via SMS, Phone, and Email

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchname %] - Items checked out: [% FOREACH checkout IN checkouts %][% checkout.item.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]. All due [% checkouts.0.date_due | $KohaDates %]"
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. You checked out: [% FOREACH checkout IN checkouts %][% checkout.item.biblio.title %][% UNLESS loop.last %], [% END %][% END %]. All due [% checkouts.0.date_due | $KohaDates %]."
email:
  subject: "Items Checked Out - [% branch.branchname %]"
  body: |
    Dear [% borrower.firstname %] [% borrower.surname %],
    
    You checked out the following items from [% branch.branchname %]:
    
    [% FOREACH checkout IN checkouts %]
    • [% checkout.item.biblio.title %]
      Barcode: [% checkout.item.barcode %]
      Due Date: [% checkout.date_due | $KohaDates %]
    
    [% END %]
    Please return items on time to avoid fines.
    
    Questions? Contact us at [% branch.branchphone %] or [% branch.branchemail %]
    
    Thank you,
    [% branch.branchname %] Staff
---
```

---

## Template Syntax Reference

### Available Variables

**For CHECKOUT notices:**
- `[% borrowernumber %]` - Patron ID
- `[% borrower.firstname %]` - Patron first name
- `[% borrower.surname %]` - Patron last name
- `[% borrower.cardnumber %]` - Patron barcode
- `[% branch.branchname %]` - Library name
- `[% branch.branchcode %]` - Library code
- `[% branch.branchphone %]` - Library phone
- `[% checkouts %]` - Array of all checkouts
- `[% checkouts.size %]` - Number of checkouts
- `[% checkouts.0.date_due %]` - First checkout due date
- `[% checkout.item.biblio.title %]` - Item title
- `[% checkout.item.barcode %]` - Item barcode
- `[% checkout.date_due %]` - Due date

**For HOLD notices:**
- `[% hold.reserve_id %]` - Hold ID
- `[% holds %]` - Array of holds
- `[% biblio.title %]` - Book title
- `[% hold.expirationdate %]` - Hold expiration

**For ODUE notices:**
- `[% overdues %]` - Array of overdue items
- `[% overdues.size %]` - Number of overdues
- `[% issue.date_due %]` - Original due date

### Template Toolkit Syntax

**Loop through items:**
```
[% FOREACH checkout IN checkouts %]
  [% checkout.item.biblio.title %]
[% END %]
```

**Conditional logic:**
```
[% IF checkouts.size > 1 %]
  You have multiple items
[% ELSE %]
  You have one item
[% END %]
```

**Join with separator:**
```
[% FOREACH item IN checkouts %]
  [% item.title %][% UNLESS loop.last %]; [% END %]
[% END %]
```

**Count items:**
```
You have [% checkouts.size %] items
```

**Loop counter:**
```
[% FOREACH item IN checkouts %]
  [% loop.count %]. [% item.title %]
[% END %]
```

---

## Best Practices

### SMS Messages (160 character limit recommended)

**Keep it brief:**
- Use abbreviations: "CPL" instead of "Centerville Public Library"
- Skip pleasantries: Get straight to the point
- Use compact list format: "Item1; Item2; Item3"

**Example - Compact CHECKOUT:**
```yaml
sms:
  text: "[% branch.branchcode %]: [% checkouts.size %] items due [% checkouts.0.date_due | $KohaDates %]. [% FOREACH c IN checkouts %][% c.item.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]"
```

### Phone/Voice Messages (30-45 seconds recommended)

**Clear and conversational:**
- Include greeting and library name
- Speak numbers clearly: "due October twenty-fifth"
- End with contact info

**Example - Natural CHECKOUT:**
```yaml
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. You checked out [% checkouts.size %] items today. [% FOREACH checkout IN checkouts %][% checkout.item.biblio.title %]. [% END %] All items are due [% checkouts.0.date_due | $KohaDates %]. For questions, call [% branch.branchphone %]. Thank you!"
```

### Email Messages (More detail)

**Include full information:**
- Professional formatting
- Complete item details
- Library contact information
- Links to account (if applicable)

---

## Testing Your Templates

### Step 1: Add Template to Koha

1. Go to: **Tools > Notices & Slips**
2. Find or create: **CHECKOUT** notice
3. Set transport: **sms** or **phone** or **email**
4. Paste your YAML template
5. Save

### Step 2: Test with Sample Data

```bash
# Check out items to a test patron
# Then run:
sudo koha-shell library -c '/usr/share/koha/bin/cronjobs/process_message_queue.pl'

# Check the result:
cat ~/CirriusImpact_archive/*.csv | tail -5
```

### Step 3: Verify Output

**Check log for template rendering:**
```bash
tail -100 ~/CirriusImpact_archive/*.log | grep "text.*=>"
```

**Check CSV for complete data:**
- All items should appear in the message
- itemsID should be populated
- Titles should be present

---

## Common Template Issues

### Issue: Items Not Showing in Loop

**Problem:** `[% FOREACH checkout IN checkouts %]` doesn't work

**Solution:** The variable might be named differently. Try:
- `[% FOREACH checkout IN issues %]`
- `[% FOREACH checkout IN CHECKOUTS %]`
- Check Koha's notice documentation for your version

### Issue: Dates Not Formatting

**Problem:** Dates show as `2025-10-25 23:59:00`

**Solution:** Use date filter:
```
[% checkout.date_due | $KohaDates %]
```

### Issue: Message Too Long for SMS

**Problem:** SMS gets truncated

**Solution:** Use compact format:
```yaml
sms:
  text: "[% branch.branchcode %]: [% checkouts.size %] items due [% checkouts.0.date_due | $KohaDates %]"
```

Or show only first N items:
```yaml
sms:
  text: "[% branch.branchname %]: [% IF checkouts.size <= 2 %][% FOREACH c IN checkouts %][% c.item.biblio.title %][% UNLESS loop.last %]; [% END %][% END %][% ELSE %][% checkouts.0.item.biblio.title %] + [% checkouts.size - 1 %] more[% END %]. Due [% checkouts.0.date_due | $KohaDates %]"
```

---

## Advanced Examples

### Conditional Message Based on Number of Items

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: |
    [% branch.branchname %]: 
    [% IF checkouts.size == 1 %]
    Checked out: [% checkouts.0.item.biblio.title %]. Due [% checkouts.0.date_due | $KohaDates %]
    [% ELSIF checkouts.size <= 3 %]
    Checked out [% checkouts.size %] items: [% FOREACH c IN checkouts %][% c.item.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]. Due [% checkouts.0.date_due | $KohaDates %]
    [% ELSE %]
    Checked out [% checkouts.size %] items including [% checkouts.0.item.biblio.title %] and [% checkouts.1.item.biblio.title %]. All due [% checkouts.0.date_due | $KohaDates %]. See account for full list.
    [% END %]
---
```

### Show Item Type or Call Number

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchname %] - Checked out: [% FOREACH checkout IN checkouts %][% checkout.item.biblio.title %] ([% checkout.item.itype %])[% UNLESS loop.last %]; [% END %][% END %]. Due [% checkouts.0.date_due | $KohaDates %]"
---
```

### Include Renewal Information

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchname %] - Checked out: [% FOREACH c IN checkouts %][% c.item.biblio.title %] (renewals left: [% c.renewals_remaining %])[% UNLESS loop.last %]; [% END %][% END %]. Due [% checkouts.0.date_due | $KohaDates %]"
---
```

---

## Template Variables Cheat Sheet

| Variable | Description | Example Value |
|----------|-------------|---------------|
| `borrowernumber` | Patron ID | 52 |
| `borrower.firstname` | First name | [% borrower.firstname %] |
| `borrower.surname` | Last name | [% borrower.surname %] |
| `borrower.cardnumber` | Card barcode | [% borrower.cardnumber %] |
| `branch.branchname` | Library name | Centerville |
| `branch.branchcode` | Library code | CPL |
| `branch.branchphone` | Library phone | 7315551234 |
| `checkouts` | Array of checkouts | (array) |
| `checkouts.size` | Number of items | 3 |
| `checkout.item.biblio.title` | Item title | Learning SQL |
| `checkout.item.barcode` | Item barcode | 39999000014334 |
| `checkout.date_due` | Due date | 2025-10-25 23:59:00 |
| `checkout.item.itype` | Item type | BOOK |
| `loop.count` | Loop counter | 1, 2, 3... |
| `loop.last` | Is last item? | true/false |

---

## Tips for Creating Great Templates

### For SMS:
1. **Start with library name** - `[% branch.branchname %]:`
2. **Keep under 160 characters** - Use compact format
3. **Include only essential info** - Title and due date
4. **End with contact** - Phone number for questions

### For Phone:
1. **Natural greeting** - "Hello [name]. This is [library]."
2. **Speak clearly** - Avoid abbreviations
3. **Repeat important info** - Due dates, phone numbers
4. **Professional closing** - "Thank you for using the library!"

### For Email:
1. **Professional subject** - "Items Checked Out - Centerville"
2. **Formatted content** - Use bullet points, headers
3. **Complete details** - Barcode, call number, due date
4. **Footer with contact** - Phone, email, hours, website

---

## Getting Help

**Template not rendering?**
- Check YAML syntax (proper indentation)
- Verify variable names match your Koha version
- Test with simple template first

**Items not appearing?**
- Check the variable name (`checkouts` vs `issues`)
- Verify patron has items checked out
- Check notice trigger conditions

**Need more examples?**
- See Koha documentation: Tools > Notices & Slips
- Ask on Koha mailing list
- Contact ByWater Solutions support

---

**Version: 1.1.9  
**Last Updated:** October 11, 2025  
**Author: Terry Rossio, CirriusImpact

