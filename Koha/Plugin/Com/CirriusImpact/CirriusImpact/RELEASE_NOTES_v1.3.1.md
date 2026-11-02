# CirriusImpact Koha Plugin v1.3.1

**Date:** 2026-07-24  
**GitLab:** https://smsgit2.cgsis.com/tcr/koha-plugin-cirriusimpact/-/releases/v1.3.1

## Template installer modes + CODE-CI support

### Added

- **`install_message_templates.pl` install modes:**
  - `--defaults` — update system-default letters (`letter.branchcode = ''`). Default when no mode is given.
  - `--ci-templates` — create/update `CODE-CI` letters only (`CHECKOUT-CI`, `HOLD-CI`, …); leave stock `CODE` alone. Point member messaging / overdue rules at the `-CI` codes for CI members only.
  - `--consortia-branch=CODE` — same letter `CODE`, branch-scoped `letter.branchcode` (repeatable / comma-separated). Creates `CHECKOUT` with `branchcode=CPL`, **not** `CHECKOUT-CPL` / `CHECKOUT-KDEMO_CPL`.
  - `--consortia-from-plugin` — same as `--consortia-branch` for every Koha branchcode with a service enabled in Configure → **Branch services** (`enabled_branches`). Values are Koha branchcodes (`CPL`, `UPL`), not CirriusImpact library IDs (`KDEMO_CPL`).
- **Plugin export** recognizes `*-CI` letter codes for filters, notification mapping, HOLDDGST digest grouping, and CHECKOUT/CHECKIN/HOLD backfill.

### Recommendation

| Site type | Typical installer mode |
|-----------|------------------------|
| Single library | `--defaults` |
| Consortia (usual) | `--consortia-branch=CPL,UPL` or `--consortia-from-plugin` |
| Alternate letter codes | `--ci-templates` (then assign `*-CI` in Koha) |

### Install

Download `koha-plugin-cirriusimpact-v1.3.1.kpz` from this GitLab release, upload via **Koha Administration → Plugins**, confirm version **1.3.1**.

```bash
# Single library (stock defaults)
sudo koha-shell <instance> -c \
  'perl .../CirriusImpact/install_message_templates.pl --defaults --no-restart'

# Consortia branch-scoped templates
sudo koha-shell <instance> -c \
  'perl .../CirriusImpact/install_message_templates.pl --consortia-from-plugin --no-restart'

# CODE-CI only (leave stock letters alone)
sudo koha-shell <instance> -c \
  'perl .../CirriusImpact/install_message_templates.pl --ci-templates --services=sms --no-restart'
```
