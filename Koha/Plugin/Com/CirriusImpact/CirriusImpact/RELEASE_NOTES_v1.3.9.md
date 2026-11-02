# CirriusImpact Koha Plugin v1.3.9

**Release date:** 2026-10-15

**GitLab:** https://smsgit2.cgsis.com/tcr/koha-plugin-cirriusimpact/-/releases/v1.3.9
**GitHub:** https://github.com/netechsys/koha-plugin-cirriusimpact/releases/tag/v1.3.9

## Summary

Installing this release updates the shipped notice templates. A library that already has the v1.3.5–v1.3.7 canned notices does not get a “need review” list for those rows.

## Changes

- CHECKOUT, CHECKIN, RENEWAL, HOLDDGST, PREDUEDGST, AUTO_RENEWALS_DGST, ODUE, ODUE2, and ODUE3 rows that are the previous canned text are rewritten to the current templates. The patron line becomes `[% borrower.borrowernumber %]`.
- A wrapped notice keeps the library’s own wording. The patron id tag is corrected. If CHECKOUT, CHECKIN, RENEWAL, or HOLDDGST still has the `----` repeat inside the sentence, it is rebuilt from the archived original so Koha can repeat each item.
- A notice that was edited and does not match a shipped template is not replaced. It remains on the Configure review list. **Download comparison** on that page saves an HTML file with the library's message, the recommended message, and the edits that make the title and date export.
- CHECKIN, CHECKOUT, RENEWAL, and HOLDDGST use Koha's `----` repeat. Each event appends one item id, and the plugin fills `{{ ci.titles }}` so one message lists every item. A `FOREACH` over `checkins` does not run: Koha does not pass that list for a check-in.

## Upgrade

Upload `koha-plugin-cirriusimpact-v1.3.9.kpz` via **Koha Administration → Plugins**. The template update runs as part of the upgrade. Open Configure afterward. The review list should contain only notices whose wording is not one of the shipped templates.
