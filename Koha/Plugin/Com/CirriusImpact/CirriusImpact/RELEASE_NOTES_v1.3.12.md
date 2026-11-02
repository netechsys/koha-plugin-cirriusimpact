# CirriusImpact Koha Plugin v1.3.12

**Release date:** 2026-11-02

**GitLab:** https://smsgit2.cgsis.com/tcr/koha-plugin-cirriusimpact/-/releases/v1.3.12
**GitHub:** https://github.com/netechsys/koha-plugin-cirriusimpact/releases/tag/v1.3.12

## Summary

Install notice templates now starts on **CI templates**. The wrap-existing choice is labeled **Library Existing**.

## Changes

- **CI templates** is the selected install mode. It writes the canned CirriusImpact notices onto the normal SMS and phone letters (`CHECKOUT`, `CHECKIN`, and the rest) and keeps that notice's name.
- **Library Existing** wraps the library's current notice text so the plugin can export it. It does not replace that wording with the canned sample.
- Consortia install is unchanged. Remove / revert follows the mode selected above.
- If Configure submits an install without a mode, CI templates is used.

## Upgrade

Upload `koha-plugin-cirriusimpact-v1.3.12.kpz` via **Koha Administration → Plugins**. Open Configure → Install notice templates. CI templates is selected. Choose Library Existing when the library's current wording should be kept.
