# CirriusImpact Koha Plugin v1.3.2

**Date:** 2026-08-03  
**GitLab:** https://smsgit2.cgsis.com/tcr/koha-plugin-cirriusimpact/-/releases/v1.3.2

## Install notice templates from Configure

### Added

- **Configure → Install notice templates** — run the CirriusImpact letter installer from the plugin UI (no SSH).
  - Modes: defaults, `CODE-CI`, consortia from plugin Branch services, or explicit Koha branchcodes
  - Services: SMS and/or phone
  - Languages: default / en / es-ES / fr-CA
  - Requires confirm-overwrite checkbox + browser confirm
- Shared module `Koha::Plugin::Com::CirriusImpact::InstallMessageTemplates` (CLI script calls the same code)

### Install

Download `koha-plugin-cirriusimpact-v1.3.2.kpz` from this GitLab release, upload via **Koha Administration → Plugins**, confirm version **1.3.2**.

After Claim + Branch services Save: open Configure → **Install notice templates** → choose mode → confirm → Install.
