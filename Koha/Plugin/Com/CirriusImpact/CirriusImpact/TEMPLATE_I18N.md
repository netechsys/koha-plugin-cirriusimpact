# CirriusImpact Koha notices — multilingual install

## Languages

| Koha `letter.lang` | Meaning | CirriusImpact CSV `language` |
|--------------------|---------|------------------------------|
| `default` | English fallback | `eng` |
| `es-ES` | Spanish | `spa` |
| `fr-CA` | French (Canadian tag) | `fre` |

Install:

```bash
sudo koha-shell <instance> -c \
  'perl /path/to/CirriusImpact/install_message_templates.pl --languages=default,es-ES,fr-CA --no-restart'
```

Requires **TranslateNotices** = On. Add `es-ES` / `fr-CA` to **OPACLanguages** (and install language packs) so patrons can select those languages.

## SMS character budget (70 vs 160)

Carriers use:

- **GSM-7** (basic Latin / some symbols): **160** chars per segment (153 if concatenated)
- **UCS-2** (any non–GSM-7 character, e.g. accented `é` `á` `ê`): **70** chars per segment (67 if concatenated)

These install templates use **GSM-7-safe ASCII** for SMS `text:` (no accents) so messages stay on the 160-char budget. Voice `script:` is also ASCII-safe for consistency; TTS still reads them fine.

Do **not** hard-truncate templates to 70 characters: titles and dates expand at send time. Prefer short wrappers + ASCII. If a library insists on accented Spanish/French SMS, plan for the 70-char UCS-2 limit (or truncate at send time in the Notification Processor).

## language column in CSV

Yes. The plugin exports `language` from the patron’s Koha language (via the notice YAML). After `_ci_normalize_language`:

- Koha `default` / `en` → `eng`
- Koha `es-ES` → `spa`
- Koha `fr-CA` → `fre`

The **Notification Processor** then selects templates / TTS using `TEXT_LANGUAGE_ALLOWED` / `VOICE_LANGUAGE_ALLOWED` (aliases include `es-es`, `fr-ca`, etc.). With `CSV_ACTIVE_HEADER=4`, it passes Koha’s rendered `messageText` through and still uses `language` for voice TTS and reporting.
