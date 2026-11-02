# CirriusImpact Koha Plugin v1.3.10

**Release date:** 2026-10-22

**GitLab:** https://smsgit2.cgsis.com/tcr/koha-plugin-cirriusimpact/-/releases/v1.3.10
**GitHub:** https://github.com/netechsys/koha-plugin-cirriusimpact/releases/tag/v1.3.10

## Summary

CI Defaults now install on the normal Koha notice. A library no longer gets a separate `CHECKOUT-CI` letter that circulation does not send.

## Changes

- **CI templates** writes the canned CirriusImpact notice onto the normal letter: the SMS and phone tabs of `CHECKOUT`, `CHECKIN`, and the other stock codes. The new row uses that notice's existing name, so it shows in the normal notice.
- The previous text is kept in a hidden comment. **Remove / revert** with CI templates restores it. If that install created the SMS or phone row, revert deletes the row. Older `CODE-CI` sample rows from earlier installs are still deleted.
- Defaults and Consortia still wrap the library's own wording. A notice that cannot list every item is left unchanged and listed on Configure. **Download comparison** shows the sentence that notice would send next to the sentence the recommended notice would send.

## Upgrade

Upload `koha-plugin-cirriusimpact-v1.3.10.kpz` via **Koha Administration → Plugins**. To put the CI default text on the notices Koha already sends, open Configure and run **Install notice templates** with **CI templates**. Notices already created as `CODE-CI` stay until **Remove / revert** is run in that same mode.
