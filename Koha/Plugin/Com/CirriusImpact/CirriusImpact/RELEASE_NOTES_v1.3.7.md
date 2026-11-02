# CirriusImpact Koha Plugin v1.3.7

**Release date:** 2026-10-06

## Summary

The plugin now claims its configuration from the production Configuration Portal by default.

## Changes

- **Default Bootstrap API URL** on **Configure** is `https://configportal.cgsis.com/koha-bootstrap/v1/claim` (previous builds defaulted to the devel portal).
- The claim API answers on every CirriusImpact server behind `configportal.cgsis.com`, and install tokens are stored centrally, so a token issued from the Configuration Portal can be claimed whichever server the library reaches.
- Install token emails from the Configuration Portal now include this public claim URL.

## Upgrade notes

- A site that already saved a Bootstrap API URL keeps it. To move such a site to production, set the field to the URL above and **Claim / Re-claim** with a fresh install token.
- No template, export or data changes; notice dates behave as in v1.3.6.

## Claim steps

1. Install or upgrade the KPZ.
2. **Plugins → CirriusImpact → Configure**.
3. Leave **Bootstrap API URL** at the default unless CirriusImpact gives you another URL.
4. Enter **Library ID** and the one-time **Install token**, then click **Claim / Re-claim**.
