# CirriusImpact Koha Plugin v1.2.2

**Date:** 2026-06-12  
**GitLab:** https://smsgit2.cgsis.com/tcr/koha-plugin-cirriusimpact/-/releases/v1.2.2

## PREDUE: fix duplicate itemsID/title on multi-item exports

### Problem

When Koha generated **multiple individual PREDUE** notices for one patron (one `message_queue` row per item), the CSV export had:

- **Correct** `messageText` per row (Koha template rendered each title)
- **Wrong** `itemsID` and `title` on every row — always the patron's **earliest-due** item

Polaris duplicate blocking and rollup then treated distinct notices as duplicates.

**Example (KMTPL):** three PREDUE rows for one patron — all showed the same `itemsID` / `title` while `messageText` named three different books.

### Root cause

`_ci_backfill_predue_identifiers()` always used `$upcoming_items[0]` for single PREDUE rows. CHECKOUT/ODUE already matched by rendered message text; PREDUE did not.

### Fix (v1.2.2)

- `_ci_extract_predue_title_from_message()` — parse title from rendered SMS/phone text
- `_ci_match_predue_upcoming_item()` — match to the correct upcoming-due item in SQL
- Fallback: `yaml_doc_index` when text match fails
- `has_all` early exit uses `next` per transport section (not `return` from entire routine)

### Also in this track

- **v1.2.1:** `TxnID` in CSV export (`message_queue.message_id`); API status fallback for holds
- **v1.2.0:** Devel/ByWater shared track baseline

### Install

Download `koha-plugin-cirriusimpact-v1.2.2.kpz` from this release, upload via **Koha Administration → Plugins**, confirm version **1.2.2**, reload plugins.

### Verify

For a patron with 2+ individual PREDUE notices, each CSV row should have matching `itemsID`, `title`, and `messageText` for the same bibliographic title.
