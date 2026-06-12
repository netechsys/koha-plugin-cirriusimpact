# CirriusImpact Koha Plugin v1.1.46

**Date:** 2026-06-12

## PREDUE: fix duplicate itemsID/title on multi-item exports

### Problem

When Koha generated **multiple individual PREDUE** notices for one patron (one `message_queue` row per item), the CSV export had:

- **Correct** `messageText` per row (Koha template rendered each title)
- **Wrong** `itemsID` and `title` on every row — always the patron's **earliest-due** item

Polaris duplicate blocking and rollup then treated distinct notices as duplicates.

**Example (KMTPL):** three PREDUE rows for JOANN LAYTON — all showed `itemsID=747281` / *Gone before goodbye* while `messageText` named *Gone before goodbye*, *The other Einstein*, and *The Martian*.

### Root cause

`_ci_backfill_predue_identifiers()` always used `$upcoming_items[0]` for single PREDUE rows. CHECKOUT/ODUE already matched by rendered message text; PREDUE did not.

### Fix

- New helpers: `_ci_extract_predue_title_from_message()`, `_ci_match_predue_upcoming_item()`
- Single PREDUE rows: parse title from rendered `text`/`script`, match against upcoming due items in SQL
- Fallback: `yaml_doc_index % item_count` (multi-doc messages)
- PREDUEDGST digest behavior unchanged

### Deploy

1. Copy updated plugin tree to Koha host:
   - `Koha/Plugin/Com/CirriusImpact.pm` (version **1.1.46**)
   - Bundle under `.../CirriusImpact/CirriusImpact/` if your install uses the nested layout
2. On Koha server:
   ```bash
   sudo koha-shell <instance> -c "perl -MKoha::Plugin -e 'Koha::Plugins->reload'"
   ```
   Or use **Home → Koha Administration → Plugins → CirriusImpact → Upgrade** if uploading a `.kpz`.
3. Confirm version in plugin UI shows **1.1.46**.
4. Optional: run `advance_notices.pl` in test mode and inspect the next CSV export for a patron with multiple PREDUE items.

### Verify

For a patron with 2+ individual PREDUE notices, each CSV row should have matching `itemsID`, `title`, and `messageText` for the same bibliographic title.
