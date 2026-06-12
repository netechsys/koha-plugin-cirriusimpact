# Digest Notices - Quick Reference Guide

## What is a Digest?

A **digest** combines multiple items into **one message** instead of sending separate messages for each item.

**Example:**
- **Without digest:** Patron checks out 4 books → Gets 4 separate messages
- **With digest:** Patron checks out 4 books → Gets 1 message listing all 4 books

## Why Use Digests?

✅ **Less annoying** - Patron gets 1 message instead of 10  
✅ **More informative** - See all items at once  
✅ **Cost effective** - Fewer SMS/phone charges  
✅ **Professional** - Better user experience  

## Quick Copy-Paste Templates

### CHECKOUT Digest (Recommended)

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchname %] - Items checked out: [% FOREACH checkout IN checkouts %][% checkout.item.biblio.title %] (due [% checkout.date_due | $KohaDates %])[% UNLESS loop.last %]; [% END %][% END %]. Questions? [% branch.branchphone %]"
---
```

### HOLD Digest (Recommended)

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
holds: [% holds_list %]
sms:
  text: "[% branch.branchname %] - [% holds.size %] hold(s) ready: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]. Pickup at [% branch.branchname %]. Expires [% holds.0.expirationdate | $KohaDates %]"
---
```

### ODUE Digest (Recommended)

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchname %] - OVERDUE: [% overdues.size %] items: [% FOREACH o IN overdues %][% o.item.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]. Return ASAP to avoid fines. [% branch.branchphone %]"
---
```

## Understanding the Loop Syntax

### Basic Loop
```
[% FOREACH checkout IN checkouts %]
  [% checkout.item.biblio.title %]
[% END %]
```

### Loop with Separator (comma or semicolon)
```
[% FOREACH checkout IN checkouts %]
  [% checkout.item.biblio.title %][% UNLESS loop.last %]; [% END %]
[% END %]
```
**Result:** `Book1; Book2; Book3` (no semicolon after last item)

### Count Items
```
You have [% checkouts.size %] items
```

### Numbered List
```
[% FOREACH checkout IN checkouts %]
  [% loop.count %]. [% checkout.item.biblio.title %]
[% END %]
```
**Result:** `1. Book1 2. Book2 3. Book3`

## Common Variables for Digests

### CHECKOUT Digest Variables
- `[% checkouts %]` - Array of all checkout items
- `[% checkouts.size %]` - Number of checkouts
- `[% checkout.item.biblio.title %]` - Title of each item
- `[% checkout.date_due %]` - Due date for each item
- `[% checkouts.0.date_due %]` - First item's due date (if all same)

### HOLD Digest Variables
- `[% holds %]` - Array of all ready holds
- `[% holds.size %]` - Number of holds
- `[% h.biblio.title %]` - Title of each hold
- `[% h.expirationdate %]` - When hold expires
- `[% h.branchcode %]` - Pickup location

### ODUE Digest Variables
- `[% overdues %]` - Array of all overdue items
- `[% overdues.size %]` - Number of overdues
- `[% o.item.biblio.title %]` - Title of each item
- `[% o.date_due %]` - Original due date
- `[% o.days_overdue %]` - Days overdue
- `[% total_fines %]` - Total fine amount

## Real-World Examples

### Scenario 1: Patron checks out 4 books

**Template:**
```yaml
sms:
  text: "[% branch.branchname %] - Checked out [% checkouts.size %] items: [% FOREACH c IN checkouts %][% c.item.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]. All due [% checkouts.0.date_due | $KohaDates %]"
```

**Output:**
```
Centerville - Checked out 4 items: Learning SQL; The poems; The bible; Can you stand the heat. All due 10/25/2025
```

### Scenario 2: Patron has 3 holds ready

**Template:**
```yaml
sms:
  text: "[% branch.branchname %] - [% holds.size %] holds ready: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]. Pickup ASAP!"
```

**Output:**
```
Centerville - 3 holds ready: Learning SQL; The poems; The bible. Pickup ASAP!
```

### Scenario 3: Patron has 3 overdue items

**Template:**
```yaml
sms:
  text: "OVERDUE: [% overdues.size %] items from [% branch.branchname %]: [% FOREACH o IN overdues %][% o.item.biblio.title %] (due [% o.date_due | $KohaDates %])[% UNLESS loop.last %]; [% END %][% END %]. Return now!"
```

**Output:**
```
OVERDUE: 3 items from Centerville: Learning SQL (due 10/05/2025); The poems (due 10/08/2025); The bible (due 10/01/2025). Return now!
```

## Tips for Great Digest Messages

### SMS (160 character limit)

**DO:**
- ✅ Use semicolons to separate items: `Book1; Book2; Book3`
- ✅ Keep library name short: Use code instead of full name
- ✅ Show count: `3 items` instead of listing if too many
- ✅ Put most important info first

**DON'T:**
- ❌ Use "and" between every item (wastes characters)
- ❌ Repeat library name for each item
- ❌ Include unnecessary words like "please", "kindly"

**Example - Compact:**
```
CPL: 5 items due 10/25: SQL; Poems; Bible; Heat; Dogs. 555-0100
```

### Phone (30-45 seconds)

**DO:**
- ✅ Speak naturally: "You have three items..."
- ✅ Pause between items: Add periods
- ✅ Repeat important info: Due date, phone number

**Example:**
```
Hello Example User. This is Centerville Library. You have three items ready for pickup. 
Learning SQL. The poems. The bible. Please pick them up by October eighteenth. 
For questions, call seven three two, five five five, three six six three. Thank you!
```

### Email (Unlimited)

**DO:**
- ✅ Use bullet points or numbered lists
- ✅ Include all details (barcode, author, due date)
- ✅ Professional formatting
- ✅ Footer with contact info

## Testing Your Digest

### Step 1: Set up test data
- Check out multiple items to one patron, OR
- Place multiple holds for one patron, OR
- Create multiple overdue items

### Step 2: Run message queue
```bash
sudo koha-shell library -c '/usr/share/koha/bin/cronjobs/process_message_queue.pl'
```

### Step 3: Check result
```bash
cat ~/CirriusImpact_archive/*.csv | tail -5
```

### Step 4: Verify
- ✅ Only 1 message for the patron (not multiple)
- ✅ Message contains all item titles
- ✅ Count matches actual number of items

## Troubleshooting Digests

### Problem: Still getting separate messages per item

**Check:**
1. Notice template has `holds:` or loop syntax
2. Koha notice aggregation is enabled
3. Messages are being batched together

### Problem: Loop not showing items

**Try different variable names:**
- `[% FOREACH checkout IN checkouts %]`
- `[% FOREACH checkout IN CHECKOUTS %]`
- `[% FOREACH checkout IN issues %]`
- `[% FOREACH item IN items %]`

Check your Koha version's documentation for correct variable names.

### Problem: Message too long for SMS

**Solution 1 - Show count + first few:**
```yaml
sms:
  text: "[% branch.branchname %]: [% items.size %] items. First 3: [% items.0.title %]; [% items.1.title %]; [% items.2.title %][% IF items.size > 3 %] + [% items.size - 3 %] more[% END %]"
```

**Solution 2 - Show only count:**
```yaml
sms:
  text: "[% branch.branchname %]: [% items.size %] holds ready. Details: check your account online or call [% branch.branchphone %]"
```

## Converting Single to Digest

### From Single Message:
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
hold: [% hold.reserve_id %]
sms:
  text: "Hold ready: [% biblio.title %]"
---
```

### To Digest Message:
```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
holds: [% holds_list %]
sms:
  text: "[% holds.size %] holds ready: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]"
---
```

**Key changes:**
1. Change `hold:` to `holds:`
2. Add loop: `[% FOREACH h IN holds %]...[% END %]`
3. Show count: `[% holds.size %]`

## See Full Examples

For complete, detailed examples with all options:
- **NOTICE_EXAMPLES.md** - 10+ examples per notice type
- **QUICKSTART.md** - Basic examples to get started
- **TESTING.md** - How to test your templates

---

**Quick Tip:** Start with Option 2 (basic digest) for each notice type, then customize as needed!

**Version: 1.1.9  
**Last Updated:** October 11, 2025  
**Author: Example User, CirriusImpact








