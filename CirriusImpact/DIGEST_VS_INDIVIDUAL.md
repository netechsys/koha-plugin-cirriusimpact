# Digest vs Individual Messages - Complete Guide

## Overview

Koha allows patrons to choose between:
- **Digest** - Receive one message with all items
- **Individual** - Receive separate messages for each item

This guide shows how to configure notices to respect patron preferences.

## How Koha Handles Digests

### Patron Messaging Preferences

In each patron's messaging preferences (patron record → Messaging tab):

**For each notice type (HOLD, ODUE, etc.):**
- ☑ **Digest only** - Combine all items into one message
- ☐ **Not checked** - Send separate message for each item

### How the Plugin Handles This

The plugin receives messages from Koha's message queue:

**If patron selected "Digest":**
- Koha creates 1 message containing all items
- Plugin exports 1 CSV row
- `messageText` column contains digest message with all items

**If patron did NOT select "Digest":**
- Koha creates 1 message per item
- Plugin exports multiple CSV rows (1 per item)
- Each `messageText` contains single item info

## CSV Output Examples

### Example 1: Digest Message (Patron Selected Digest)

**Patron has 3 holds ready, selected "Digest only"**

Koha creates: **1 message** with all 3 items

CSV output: **1 row**
```csv
commType,language,notificationType,...,title,messageText
S,default,HOLD,...,"Learning SQL; The poems; The bible","Centerville - 3 holds ready: Learning SQL; The poems; The bible. Pickup ASAP"
```

### Example 2: Individual Messages (Patron Did NOT Select Digest)

**Patron has 3 holds ready, did NOT select "Digest only"**

Koha creates: **3 messages** (1 per item)

CSV output: **3 rows**
```csv
commType,language,notificationType,...,title,messageText
S,default,HOLD,...,Learning SQL,"Centerville - Hold ready: Learning SQL. Pickup ASAP"
S,default,HOLD,...,The poems,"Centerville - Hold ready: The poems. Pickup ASAP"
S,default,HOLD,...,The bible,"Centerville - Hold ready: The bible. Pickup ASAP"
```

## Notice Template Configuration

### Template Structure for Both Modes

Create ONE notice template that works for BOTH digest and individual:

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
holds: [% holds_list %]
sms:
  text: |
    [% branch.branchname %] - 
    [% IF holds.size > 1 %]
    [% holds.size %] holds ready: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]
    [% ELSE %]
    Hold ready: [% biblio.title %]
    [% END %]
    Pickup ASAP
call:
  script: |
    Hello [% borrower.firstname %]. This is [% branch.branchname %]. 
    [% IF holds.size > 1 %]
    You have [% holds.size %] items ready for pickup: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %], [% END %][% END %].
    [% ELSE %]
    You have one item ready for pickup: [% biblio.title %].
    [% END %]
    Please pick up soon. For questions, call [% branch.branchphone %].
---
```

**How it works:**
- **Digest mode**: `holds.size > 1` → Shows all items in list
- **Individual mode**: `holds.size == 1` → Shows single item
- **Same template** works for both patron preferences!

## Complete Copy-Paste Examples

### HOLD Notices (Digest + Individual, SMS + Phone)

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
holds: [% holds_list %]
sms:
  text: |
    [% branch.branchname %] - 
    [% IF holds.size > 1 %]
    [% holds.size %] holds ready: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]. Pickup by [% holds.0.expirationdate | $KohaDates %]
    [% ELSE %]
    Hold ready: [% biblio.title %]. Pickup by [% hold.expirationdate | $KohaDates %]
    [% END %]
    Questions? [% branch.branchphone %]
call:
  script: |
    Hello [% borrower.firstname %]. This is [% branch.branchname %]. 
    [% IF holds.size > 1 %]
    You have [% holds.size %] items ready for pickup: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %], [% END %][% END %]. Please pick them up by [% holds.0.expirationdate | $KohaDates %].
    [% ELSE %]
    You have one item ready for pickup: [% biblio.title %]. Please pick it up by [% hold.expirationdate | $KohaDates %].
    [% END %]
    For questions, call [% branch.branchphone %]. Thank you!
---
```

**Patron with Digest enabled:**
- CSV: 1 row with messageText containing all 3 titles

**Patron without Digest:**
- CSV: 3 rows, each with messageText for one title

### CHECKOUT Notices (Digest + Individual, SMS + Phone)

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: |
    [% branch.branchname %] - 
    [% IF checkouts.size > 1 %]
    Checked out [% checkouts.size %] items: [% FOREACH c IN checkouts %][% c.item.biblio.title %] (due [% c.date_due | $KohaDates %])[% UNLESS loop.last %]; [% END %][% END %]
    [% ELSE %]
    Checked out: [% biblio.title %]. Due [% checkout.date_due | $KohaDates %]
    [% END %]
    Questions? [% branch.branchphone %]
call:
  script: |
    Hello [% borrower.firstname %]. This is [% branch.branchname %]. 
    [% IF checkouts.size > 1 %]
    You checked out [% checkouts.size %] items today: [% FOREACH c IN checkouts %][% c.item.biblio.title %] due [% c.date_due | $KohaDates %][% UNLESS loop.last %], [% END %][% END %]. 
    [% ELSE %]
    You checked out [% biblio.title %] due [% checkout.date_due | $KohaDates %].
    [% END %]
    Thank you for visiting the library!
---
```

### ODUE Notices (Digest + Individual, SMS + Phone)

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: |
    [% branch.branchname %] OVERDUE - 
    [% IF overdues.size > 1 %]
    [% overdues.size %] items: [% FOREACH o IN overdues %][% o.item.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]. Fines: $[% total_fines %]
    [% ELSE %]
    [% biblio.title %] was due [% issue.date_due | $KohaDates %]. Fine: $[% fine_amount %]
    [% END %]
    Return ASAP! [% branch.branchphone %]
call:
  script: |
    Hello [% borrower.firstname %]. This is [% branch.branchname %]. 
    [% IF overdues.size > 1 %]
    You have [% overdues.size %] overdue items: [% FOREACH o IN overdues %][% o.item.biblio.title %][% UNLESS loop.last %], [% END %][% END %]. Your total fines are $[% total_fines %].
    [% ELSE %]
    You have one overdue item: [% biblio.title %] was due [% issue.date_due | $KohaDates %]. Your fine is $[% fine_amount %].
    [% END %]
    Please return immediately to avoid additional fines. Call [% branch.branchphone %] with questions.
---
```

## CSV Output for Multiple Items

### Scenario: Patron with Digest Enabled + 3 Items

**Koha behavior:** Creates 1 message

**CSV output:** 1 row
```csv
S,default,HOLD,,,[% borrower.firstname %],[% borrower.surname %],7315551234,...,CPL,Centerville,413,,Learning SQL; The poems; The bible,...,"Centerville - 3 holds ready: Learning SQL; The poems; The bible. Pickup ASAP"
```

**Key points:**
- One CSV row
- `title` column: May show first title or concatenated titles
- `messageText` column: Complete message with all items
- `itemsID` column: First item's ID

### Scenario: Patron WITHOUT Digest + 3 Items

**Koha behavior:** Creates 3 messages

**CSV output:** 3 rows
```csv
S,default,HOLD,,,[% borrower.firstname %],[% borrower.surname %],7315551234,...,CPL,Centerville,413,,Learning SQL,...,"Centerville - Hold ready: Learning SQL. Pickup ASAP"
S,default,HOLD,,,[% borrower.firstname %],[% borrower.surname %],7315551234,...,CPL,Centerville,721,,The poems,...,"Centerville - Hold ready: The poems. Pickup ASAP"
S,default,HOLD,,,[% borrower.firstname %],[% borrower.surname %],7315551234,...,CPL,Centerville,193,,The bible,...,"Centerville - Hold ready: The bible. Pickup ASAP"
```

**Key points:**
- Three CSV rows
- Each row has different `itemsID` and `title`
- Each `messageText` is for single item
- Patron gets 3 separate messages

## Advanced Template: Detect Digest vs Individual

You can detect which mode is active and customize the message:

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
holds: [% holds_list %]
sms:
  text: |
    [% IF holds.size > 1 %]
    [%# DIGEST MODE #%]
    [% branch.branchname %] - [% holds.size %] holds ready:
    [% FOREACH h IN holds %]
    • [% h.biblio.title %] (expires [% h.expirationdate | $KohaDates %])
    [% END %]
    Pickup soon to avoid cancellation.
    [% ELSE %]
    [%# INDIVIDUAL MODE #%]
    [% branch.branchname %] - Hold ready: [% biblio.title %]
    Pickup by [% hold.expirationdate | $KohaDates %] at [% branch.branchname %]
    Questions? [% branch.branchphone %]
    [% END %]
call:
  script: |
    Hello [% borrower.firstname %]. This is [% branch.branchname %]. 
    [% IF holds.size > 1 %]
    [%# DIGEST MODE - Natural voice listing #%]
    You have [% holds.size %] items ready for pickup. The titles are: [% FOREACH h IN holds %][% h.biblio.title %][% IF loop.last %].[% ELSE %], [% END %][% END %] Please pick them up at your earliest convenience. They will be held until [% holds.0.expirationdate | $KohaDates %].
    [% ELSE %]
    [%# INDIVIDUAL MODE - Single item #%]
    You have one item ready for pickup: [% biblio.title %]. Please pick it up by [% hold.expirationdate | $KohaDates %] at [% branch.branchname %].
    [% END %]
    For questions, call [% branch.branchphone %]. Thank you!
---
```

## Complete Examples (SMS + Phone, Both Modes)

### HOLD Notice - Universal Template

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

### CHECKOUT Notice - Universal Template

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

### ODUE Notice - Universal Template

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %] OVERDUE: [% IF overdues.size > 1 %][% overdues.size %] items: [% FOREACH o IN overdues %][% o.item.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]. Total fines: $[% total_fines %][% ELSE %][% biblio.title %] was due [% issue.date_due | $KohaDates %]. Fine: $[% fine_amount %][% END %]. Return now!"
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. [% IF overdues.size > 1 %]You have [% overdues.size %] overdue items: [% FOREACH o IN overdues %][% o.item.biblio.title %][% UNLESS loop.last %], [% END %][% END %]. Total fines: $[% total_fines %][% ELSE %]You have one overdue item: [% biblio.title %] was due [% issue.date_due | $KohaDates %]. Fine: $[% fine_amount %][% END %]. Return immediately. Call [% branch.branchphone %]."
---
```

## Best Practice Examples

### HOLD - Polished for Both Modes

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
holds: [% holds_list %]
sms:
  text: |
    [% branch.branchname %] - 
    [% IF holds.size > 1 %]
    You have [% holds.size %] holds ready for pickup:
    [% FOREACH h IN holds %]
    • [% h.biblio.title %]
    [% END %]
    All available until [% holds.0.expirationdate | $KohaDates %]
    [% ELSE %]
    Your hold is ready: [% biblio.title %]
    Available until [% hold.expirationdate | $KohaDates %]
    [% END %]
    Pickup at [% branch.branchname %]. [% branch.branchphone %]
call:
  script: |
    Hello [% borrower.firstname %]. This is [% branch.branchname %]. 
    [% IF holds.size > 1 %]
    You have [% holds.size %] items ready for pickup. The titles are: [% FOREACH h IN holds %][% h.biblio.title %][% IF loop.last %].[% ELSE %], [% END %][% END %] All items will be held until [% holds.0.expirationdate | $KohaDates %]. Please pick them up at your earliest convenience.
    [% ELSE %]
    You have one item ready for pickup: [% biblio.title %]. It will be held until [% hold.expirationdate | $KohaDates %]. Please pick it up at [% branch.branchname %].
    [% END %]
    For questions, call [% branch.branchphone %]. Thank you!
---
```

### CHECKOUT - With Due Date Emphasis

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: |
    [% branch.branchname %] - Thank you for visiting!
    [% IF checkouts.size > 1 %]
    You checked out [% checkouts.size %] items: [% FOREACH c IN checkouts %][% c.item.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]
    All due: [% checkouts.0.date_due | $KohaDates %]
    [% ELSE %]
    You checked out: [% biblio.title %]
    Due: [% checkout.date_due | $KohaDates %]
    [% END %]
    Renew online or call [% branch.branchphone %]
call:
  script: |
    Hello [% borrower.firstname %]. This is [% branch.branchname %]. 
    [% IF checkouts.size > 1 %]
    You checked out [% checkouts.size %] items today: [% FOREACH c IN checkouts %][% c.item.biblio.title %][% UNLESS loop.last %], [% END %][% END %]. All items are due [% checkouts.0.date_due | $KohaDates %].
    [% ELSE %]
    You checked out [% biblio.title %] today. It is due [% checkout.date_due | $KohaDates %].
    [% END %]
    You can renew online or call [% branch.branchphone %]. Thank you for visiting!
---
```

### ODUE - Escalating Based on Count

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: |
    [% branch.branchname %] OVERDUE NOTICE:
    [% IF overdues.size > 1 %]
    You have [% overdues.size %] overdue items. Total fines: $[% total_fines %]
    Items: [% FOREACH o IN overdues %][% o.item.biblio.title %] (due [% o.date_due | $KohaDates %])[% UNLESS loop.last %]; [% END %][% END %]
    [% ELSE %]
    [% biblio.title %] is overdue (due [% issue.date_due | $KohaDates %])
    Current fine: $[% fine_amount %]
    [% END %]
    Return immediately to stop fines! [% branch.branchphone %]
call:
  script: |
    Hello [% borrower.firstname %]. This is [% branch.branchname %]. 
    [% IF overdues.size > 1 %]
    You have [% overdues.size %] overdue items. [% FOREACH o IN overdues %][% o.item.biblio.title %] was due [% o.date_due | $KohaDates %]. [% END %] Your total fines are $[% total_fines %]. Please return these items immediately to prevent your account from being suspended.
    [% ELSE %]
    You have one overdue item: [% biblio.title %] was due [% issue.date_due | $KohaDates %]. Your current fine is $[% fine_amount %]. Please return it immediately.
    [% END %]
    For questions, call [% branch.branchphone %]. Thank you.
---
```

## Template Syntax Reference

### Detect Digest vs Individual
```
[% IF holds.size > 1 %]
  DIGEST MODE - multiple items
[% ELSE %]
  INDIVIDUAL MODE - single item
[% END %]
```

### Access Items in Digest
```
[% FOREACH h IN holds %]
  [% h.biblio.title %]
[% END %]
```

### Access Single Item (Individual)
```
[% biblio.title %]
[% hold.expirationdate %]
[% checkout.date_due %]
```

### Count Items
```
[% holds.size %]
[% checkouts.size %]
[% overdues.size %]
```

## Testing Both Modes

### Test Digest Mode

1. Go to patron record → Messaging tab
2. For HOLD notice: Check ☑ "Digest only"
3. Place 3 holds for the patron
4. Make holds available
5. Run message queue

**Expected:** 1 CSV row with all 3 titles in messageText

### Test Individual Mode

1. Go to patron record → Messaging tab
2. For HOLD notice: Uncheck ☐ "Digest only"
3. Place 3 holds for the patron
4. Make holds available
5. Run message queue

**Expected:** 3 CSV rows, each with one title in messageText

## Troubleshooting

### Problem: Getting individual messages even with Digest checked

**Check:**
1. Patron messaging preferences → Verify "Digest only" is checked
2. Notice template → Ensure it has `holds:` or array syntax
3. Koha version → Digest feature requires Koha 17.11+

### Problem: Digest message only shows first item

**Cause:** Template doesn't loop through items

**Fix:** Add FOREACH loop:
```yaml
sms:
  text: "[% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]"
```

### Problem: Can't access holds.size

**Try different variable names:**
- `[% holds.size %]`
- `[% holds.count %]`
- `[% HOLDS.size %]`

Check your Koha version's notice documentation for correct syntax.

## Summary

### For Digest Messages (Patron Selected Digest)
- ✅ Koha creates 1 message with all items
- ✅ Plugin exports 1 CSV row
- ✅ `messageText` contains full digest with all items
- ✅ Use `[% FOREACH %]` loop in template

### For Individual Messages (Patron Did NOT Select Digest)
- ✅ Koha creates 1 message per item
- ✅ Plugin exports multiple CSV rows
- ✅ Each `messageText` contains single item
- ✅ Use single item variables in template

### Universal Template Strategy
- ✅ Create ONE template for both modes
- ✅ Use `[% IF holds.size > 1 %]` to detect mode
- ✅ Provide both digest and individual formatting
- ✅ Same template works for all patrons

---

**Version:** 1.1.9  
**messageText column:** Added in v1.1.7  
**Last Updated:** October 11, 2025  
**Author: Terry Rossio, CirriusImpact


