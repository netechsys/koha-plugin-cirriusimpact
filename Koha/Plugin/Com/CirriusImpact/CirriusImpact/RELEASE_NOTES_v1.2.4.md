# CirriusImpact Koha Plugin v1.2.4

**Date:** 2026-07-20  
**GitLab:** https://smsgit2.cgsis.com/tcr/koha-plugin-cirriusimpact/-/releases/v1.2.4  
**GitHub:** https://github.com/netechsys/koha-plugin-cirriusimpact/releases/tag/v1.2.4

## Multilingual notice templates (English / Spanish / French)

### Added

- **`install_message_templates.pl`** installs CirriusImpact YAML notices for three Koha `letter.lang` values:
  - `default` — English fallback
  - `es-ES` — Spanish
  - `fr-CA` — French
- CLI: `--languages=default,es-ES,fr-CA` and `--no-restart`
- Upserts by `(module, code, message_transport_type, lang)` so languages do not overwrite each other
- **`TEMPLATE_I18N.md`** — install notes, SMS GSM-7 vs UCS-2 guidance, language export mapping

### SMS wording (GSM-7 safe)

Spanish and French **SMS** `text:` bodies use ASCII (no accents) so carriers stay on GSM-7 (~160 chars/segment) instead of UCS-2 (~70). Titles and dates still expand at send time.

### CSV `language` column → eng / spa / fre

`_ci_normalize_language()` maps Koha IETF tags to CirriusImpact / Notification Processor codes:

| Koha patron / notice lang | CSV `language` |
|---------------------------|----------------|
| `default`, `en`, … | `eng` |
| `es-ES`, `es`, … | `spa` |
| `fr-CA`, `fr`, … | `fre` |

Requires **TranslateNotices** and the matching entries in **OPACLanguages** (plus language packs) for patrons to select Spanish/French.

### Install

Download `koha-plugin-cirriusimpact-v1.2.4.kpz` from this release, upload via **Koha Administration → Plugins**, confirm version **1.2.4**.

Re-run the template installer on each Koha instance:

```bash
sudo koha-shell <instance> -c \
  'perl .../CirriusImpact/install_message_templates.pl --languages=default,es-ES,fr-CA --no-restart'
```
