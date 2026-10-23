# CirriusImpact Koha Plugin v1.3.6

**Date:** 2026-10-05  
**GitLab:** https://smsgit2.cgsis.com/tcr/koha-plugin-cirriusimpact/-/releases/v1.3.6  
**GitHub:** https://github.com/netechsys/koha-plugin-cirriusimpact/releases/tag/v1.3.6

## Notice dates follow the library's Koha date format

Before v1.3.6 the same Koha site could send dates in different formats depending on the notice, and some dates had the day and month swapped:

- Templates using `$KohaDates` (PREDUEDGST, DUEDGST, ODUE*, AUTO_RENEWALS_DGST, HOLD) followed Koha's `dateformat` preference, while `{{ ci.due }}` (CHECKOUT, CHECKIN, RENEWAL, HOLDDGST) was always `M/D/YYYY`.
- While writing the export file the plugin rewrote every date in the message text on the assumption that it was `DD/MM/YYYY`. Dates that were already month-first were swapped whenever the day was 12 or less: a hold ready until 7 October was sent as "Pickup by 7/10/2026", and a PREDUEDGST item due 7 October as "(7/10/2026)". Dates on the 13th or later were not affected, which is why the problem looked notice-specific.

### What v1.3.6 does

Every patron-facing date is formatted once, from Koha's **`dateformat`** system preference, exactly like `$KohaDates`:

| Koha `dateformat` | SMS text (7 October 2026) | Voice script |
|-------------------|---------------------------|--------------|
| `us` | `10/07/2026` | "October 7" |
| `metric` | `07/10/2026` | "7 October" |
| `dmydot` | `07.10.2026` | "7 October" |
| `iso` | `2026-10-07` | "7 October" |

- **SMS:** `{{ ci.due }}`, `$KohaDates` and the plugin's own fallback text all use the library's format. The text is not rewritten afterwards.
- **Voice:** dates in the script are read in the library's format and spoken with the month name, in the notice language: English "October 7" (US) or "7 October", Spanish "7 de octubre", French "7 octobre" ("1er" for the first). The year is spoken only when it is not the current year ("January 5, 2027"). Month names are unaccented ASCII, matching the canned French and Spanish templates.
- **Export `date` column:** unchanged, always `DD/MM/YYYY`, for the Notification Processor.

No template changes are needed and no templates are rewritten on upgrade. `dateformat` is one setting per Koha instance; set it in **Administration → System preferences → I18N/L10N → dateformat**.

### Removed

- `_convert_dates_in_text_to_us_format` and `_format_date_us` (the US-only rewrite that caused the swaps).

### Tested

- Every calendar day 2024–2030 (2,557 days, leap days included), from Koha dates, date-times and the plugin's internal `DD/MM/YYYY`, in all four `dateformat` values, with English, Spanish and French voice: 153,429 checks, 0 failures.
- On KohaLab, the plugin's dates match Koha's own `$KohaDates` filter and `output_pref` for every day 2024–2030 in all four formats (20,456 checks, 0 failures).
- End-to-end on KohaLab (test mode) with `us` and `metric`: CHECKOUT, CHECKIN, RENEWAL, HOLDDGST, PREDUEDGST, DUEDGST, ODUE/ODUE2/ODUE3 and AUTO_RENEWALS_DGST, SMS and voice, with due dates on the 3rd, 11th and 21st and a hold expiring on the 12th.

### Install

Download `koha-plugin-cirriusimpact-v1.3.6.kpz` from the release, upload via **Koha Administration → Plugins**, and confirm version **1.3.6**. Check that the `dateformat` system preference matches the library's country.
