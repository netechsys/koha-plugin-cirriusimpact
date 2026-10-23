# CirriusImpact Koha Plugin v1.3.4

**Date:** 2026-09-17  
**GitLab:** https://smsgit2.cgsis.com/tcr/koha-plugin-cirriusimpact/-/releases/v1.3.4

## Defaults wrap existing notices + Remove/revert

### Changed (from v1.3.2 install UI)

**Defaults** and **Consortia** modes no longer overwrite stock notice wording with canned CirriusImpact sample text.

They now:

1. Read the existing Koha `letter` row (same `module` / `code` / transport / `lang` / `branchcode`)
2. Skip rows that already contain `CirriusImpact: yes`, or that have no text to wrap
3. Wrap the current notice body in CirriusImpact YAML, for example:

```yaml
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "<original notice text>"
---
```

Phone notices use `call: script:` instead of `sms: text:`.

4. Append the original notice as hidden Template Toolkit comments for later undo:

```
[%# Original Notice Template %]
[%# ...original lines... %]
```

**CI templates** mode is unchanged in purpose: it still installs **canned** sample notices as `CODE-CI` only (stock codes left alone). Prefer Defaults/Consortia wrap for production sites that keep using stock letter codes.

### Added

- **Configure → Remove / revert templates** — undoes an install for the same mode / services / languages / branches:
  - Defaults & Consortia: restore archived original text from the TT comment block (falls back to `sms.text` / `call.script` if comments are missing)
  - CI templates: **delete** matching canned `CODE-CI` rows
- CLI: `install_message_templates.pl --remove` with the same mode flags
- Shared `InstallMessageTemplates::run_remove(...)`

### Install

Download `koha-plugin-cirriusimpact-v1.3.4.kpz` from this GitLab release, upload via **Koha Administration → Plugins**, confirm version **1.3.4**.

After Claim + Branch services Save:

1. Configure → **Install notice templates** → Defaults (or Consortia) → confirm → Install  
2. To undo: **Remove / revert templates** with the same mode selection → confirm → Remove
