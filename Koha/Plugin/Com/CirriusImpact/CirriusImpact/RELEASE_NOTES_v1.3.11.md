# CirriusImpact Koha Plugin v1.3.11

**Release date:** 2026-10-23

**GitLab:** https://smsgit2.cgsis.com/tcr/koha-plugin-cirriusimpact/-/releases/v1.3.11
**GitHub:** https://github.com/netechsys/koha-plugin-cirriusimpact/releases/tag/v1.3.11

## Summary

The automatic-renewal digest lists only the items that were renewed.

## Changes

- `AUTO_RENEWALS_DGST` SMS and phone notices skip any checkout with `auto_renew_error`. The spoken or texted sentence, and the item ids the plugin exports, include only renewed items and their new due dates.
- English, Spanish, and French shipped templates are updated.
- A library that edited this notice keeps that wording. The shipped digest is rewritten when this package is installed.

## Upgrade

Upload `koha-plugin-cirriusimpact-v1.3.11.kpz` via **Koha Administration → Plugins**. After the upgrade, open the `AUTO_RENEWALS_DGST` notice and confirm the SMS and phone text skips `auto_renew_error`. A notice the library changed stays in place and is listed on Configure.
