# CirriusImpact Koha Plugin v1.3.5

**Date:** 2026-09-30  
**GitLab:** https://smsgit2.cgsis.com/tcr/koha-plugin-cirriusimpact/-/releases/v1.3.5  
**GitHub:** https://github.com/netechsys/koha-plugin-cirriusimpact/releases/tag/v1.3.5

## Multi-item notices (incremental vs all-at-once)

Previous canned CirriusImpact templates described a single item per notice. Koha builds several notices from more than one item, so a patron checking out three books, or receiving a pre-due digest for several items, only saw one title.

Koha produces multi-item notices in two different ways (see Springshare's write-up, [Notices that Koha builds incrementally vs all at once](https://github.com/springshare/koha-plugin-webhook-notifications#notices-that-koha-builds-incrementally-vs-all-at-once)). v1.3.5 templates follow both.

### Incremental: CHECKOUT, CHECKIN, RENEWAL, HOLDDGST

Koha splits the letter on `----` into header / body / footer. The first event queues the whole letter; every later event for the same patron (while the message is still pending) appends only the body. The templates therefore declare an empty list in the header and emit one id per event in the body:

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Checked out: {{ ci.titles }}. Due {{ ci.due }}."
checkouts:
----
  - [% checkout.issue_id %]
----
---
```

| Notice | List key | Body line |
|--------|----------|-----------|
| CHECKOUT | `checkouts:` | `- [% checkout.issue_id %]` |
| RENEWAL | `checkouts:` | `- [% checkout.issue_id %]` |
| CHECKIN | `old_checkouts:` | `- [% old_checkout.issue_id %]` |
| HOLDDGST | `holds:` | `- [% hold.reserve_id %]` |

At export time the plugin resolves the ids to items and fills these placeholders:

| Placeholder | Value |
|-------------|-------|
| `{{ ci.titles }}` | Titles joined with `; ` (SMS) |
| `{{ ci.titles_comma }}` | Titles joined with `, ` (voice) |
| `{{ ci.due }}` | Unique due dates (hold: pickup-by date), `M/D/YYYY`, joined with `, ` |
| `{{ ci.count }}` | Number of items |

### All at once: PREDUEDGST, DUEDGST, AUTO_RENEWALS_DGST, ODUE, ODUE2, ODUE3

These are rendered in one pass by a cron job, so the templates loop over the object Koha provides:

| Notice | Koha object | Example |
|--------|-------------|---------|
| PREDUEDGST, DUEDGST | `checkouts` | `[% FOREACH c IN checkouts %][% c.title %] ([% c.date_due \| $KohaDates %])…[% END %]` |
| ODUE, ODUE2, ODUE3 | `overdues` | `[% FOREACH o IN overdues %][% o.item.biblio.title %] ([% o.date_due \| $KohaDates %])…[% END %]` |
| AUTO_RENEWALS_DGST | `checkouts` | `[% FOREACH c IN checkouts %][% c.item.biblio.title %][% IF c.auto_renew_error %] (not renewed)[% END %]…[% END %]` |

Each also emits `checkouts: "<issue_id>,<issue_id>,"` so the plugin can fill item fields in the CSV.

### One message, one CSV row

A multi-item notice is sent as **one** SMS / call listing all items. The CSV row carries every item: `itemsID` and `title` are `; `-joined, and `date` is the first item's date. The Notification Processor uses Koha's rendered `messageText` unchanged.

### Automatic template upgrade

On plugin upgrade (upload the KPZ over v1.3.4 or earlier) the plugin rewrites untouched canned CirriusImpact templates for the ten notices above to the new shapes. It matches every canned version shipped since v1.1.43, in every language, including `CODE-CI` and branch rows.

- Rows created by **Defaults / Consortia wrap** (library's own notice text) are **not** changed.
- CirriusImpact rows that were **edited locally** are **not** changed; they are listed on **Configure** in a yellow "Notice templates need review" box. Update them by hand using the shapes above, or reinstall with Configure → Install notice templates.
- Preview or re-run from the command line:

```bash
sudo koha-shell <instance> -c \
  'perl /path/to/CirriusImpact/install_message_templates.pl --upgrade --dry-run --no-restart'
```

### Added

- **DUEDGST** SMS and voice templates (en / es-ES / fr-CA) and export of `DUE` / `DUEDGST` notices.
- `install_message_templates.pl --upgrade [--dry-run]` and `InstallMessageTemplates::run_upgrade`.

### Fixed

- ODUE / ODUE2 / ODUE3 are exported even when `overduerules` is empty or uses other codes; `ODUE-CI` variants are recognized.
- `AUTO_RENEWALS_DGST` template referenced a nonexistent `auto_renewals` object; it now loops over `checkouts`.
- `CirriusImpact_TEST_MODE` no longer loops forever re-reading the same pending messages.
- Trailing MARC punctuation (`Title /`) is stripped from listed titles.

### Install

Download `koha-plugin-cirriusimpact-v1.3.5.kpz` from the release, upload via **Koha Administration → Plugins**, and confirm version **1.3.5**. Then open **Configure** and check for the "Notice templates need review" box.
