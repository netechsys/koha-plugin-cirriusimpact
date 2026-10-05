# CirriusImpact Koha notices — multilingual install

## Install modes

| Mode | Writes | Typical use |
|------|--------|-------------|
| `--defaults` | Stock `CODE` at `branchcode=''` | Single library (default if no mode given) |
| `--ci-templates` | `CODE-CI` only; stock untouched | Alternate letter codes for CI members |
| `--consortia-branch=CPL[,UPL…]` | Same `CODE`, branch-scoped rows | Consortia |
| `--consortia-from-plugin` | Same for Configure → Branch services (enabled branches) | Consortia after matrix Save |

`--consortia-branch=CPL` creates `CHECKOUT` with `branchcode=CPL`, not `CHECKOUT-CPL`. The plugin also exports `*-CI` letter codes.

**From the plugin UI:** Configure → **Install notice templates** (same options; no SSH).

## Languages

| Koha `letter.lang` | Meaning | CirriusImpact CSV `language` |
|--------------------|---------|------------------------------|
| `default` | Koha Default tab (content from `--default-language`) | maps from source lang |
| `en` | English | `eng` |
| `es-ES` | Spanish | `spa` |
| `fr-CA` | French (Canadian tag) | `fre` |

Install (all four rows by default; Default tab filled from English):

```bash
sudo koha-shell <instance> -c \
  'perl /path/to/CirriusImpact/install_message_templates.pl --defaults --no-restart'
```

Consortia from plugin branches:

```bash
sudo koha-shell <instance> -c \
  'perl /path/to/CirriusImpact/install_message_templates.pl --consortia-from-plugin --no-restart'
```

Spanish-primary library (Default tab = Spanish; still installs `en`, `es-ES`, `fr-CA`):

```bash
sudo koha-shell <instance> -c \
  'perl /path/to/CirriusImpact/install_message_templates.pl --default-language=spa --no-restart'
```

SMS only (skip phone/voice templates):

```bash
sudo koha-shell <instance> -c \
  'perl /path/to/CirriusImpact/install_message_templates.pl --services=sms --no-restart'
```

Aliases for `--default-language`: `en`/`eng`, `es-ES`/`spa`, `fr-CA`/`fre`.

Optional: `--services=sms`, `--services=phone`, or `--services=sms,phone` (default both). Aliases: `text`→sms, `voice`/`call`→phone. `--transports` is accepted as an alias for `--services`.

Optional: `--languages=default,en,es-ES,fr-CA` to limit which `letter.lang` rows are written.

Requires **TranslateNotices** = On. Add `en` / `es-ES` / `fr-CA` to **OPACLanguages** (and install language packs) so patrons can select those languages and notice tabs appear.

## Multi-item notices (v1.3.5)

Koha builds some notices incrementally and others all at once; templates must match (details and examples in [RELEASE_NOTES_v1.3.5.md](RELEASE_NOTES_v1.3.5.md)).

| Koha builds | Notices | Template shape |
|-------------|---------|----------------|
| Incrementally (one body appended per event) | CHECKOUT, CHECKIN, RENEWAL, HOLDDGST | Header ends with an empty list key (`checkouts:` / `old_checkouts:` / `holds:`), body between `----` lines is `  - [% checkout.issue_id %]` (CHECKIN `old_checkout.issue_id`, HOLDDGST `hold.reserve_id`); text uses `{{ ci.titles }}` (SMS), `{{ ci.titles_comma }}` (voice), `{{ ci.due }}` |
| All at once (cron) | PREDUEDGST, DUEDGST, AUTO_RENEWALS_DGST, ODUE, ODUE2, ODUE3 | `[% FOREACH c IN checkouts %]…[% END %]` (ODUE*: `o IN overdues`) in the text, plus `checkouts: "[% FOREACH … %][% c.issue_id %],[% END %]"` |

Do not put anything but the id line between the `----` markers: Koha repeats that part once per event.

### Upgrading existing templates

Uploading a newer KPZ rewrites untouched canned templates automatically; locally edited ones are listed on Configure. To preview or re-run:

```bash
sudo koha-shell <instance> -c \
  'perl /path/to/CirriusImpact/install_message_templates.pl --upgrade --dry-run --no-restart'
```

Drop `--dry-run` to apply.

## Notice dates (v1.3.6)

Patron-facing dates follow Koha's **`dateformat`** system preference (Administration → System preferences → I18N/L10N), the same as `$KohaDates`. `{{ ci.due }}` and `[% … | $KohaDates %]` therefore produce the same format on every notice:

| `dateformat` | SMS (7 October 2026) | Voice |
|--------------|----------------------|-------|
| `us` | `10/07/2026` | "October 7" |
| `metric` | `07/10/2026` | "7 October" |
| `dmydot` | `07.10.2026` | "7 October" |
| `iso` | `2026-10-07` | "7 October" |

Voice scripts are converted to spoken dates with the month name in the notice language (Spanish "7 de octubre", French "7 octobre", "1er" for the first); the year is spoken only when it is not the current year. Write dates in templates with `$KohaDates` or `{{ ci.due }}`; do not hard-code a format. The CSV `date` column is always `DD/MM/YYYY`. Details: [RELEASE_NOTES_v1.3.6.md](RELEASE_NOTES_v1.3.6.md).

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
