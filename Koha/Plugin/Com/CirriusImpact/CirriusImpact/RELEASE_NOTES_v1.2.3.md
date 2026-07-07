# CirriusImpact Koha Plugin v1.2.3

**Date:** 2026-07-07  
**GitHub:** https://github.com/netechsys/koha-plugin-cirriusimpact/releases/tag/v1.2.3

## HOLD notices: wrong overdue messageText on CSV export (KMTPL / Middletown)

### Problem

HOLD notices exported with correct `notificationType` (2), `kohaNotificationType` (HOLD), patron, title, and branch — but **SMS `messageText` used overdue wording**:

`[Library] PATRON, You have item(s) that are now overdue: TITLE...`

Phone (`V`) rows often had **blank** `messageText` even though `message_queue.content` contained the correct `call: script:`.

Koha `message_queue` content **did** include the correct scripts, for example:

```yaml
sms:
  text: "Dear THOMAS GEDEN, Your hold for This is Spın̈al Tap ... is available for pickup."
call:
  script: "Your item is available for pick up. Title: ..."
```

### Root cause

1. Koha sometimes stores CirriusImpact YAML on **one line** between `---` markers. That format is invalid for `YAML::XS::Load`.
2. On parse failure the plugin silently substituted `{ CirriusImpact: yes }` only — **dropping** `sms.text`, `call.script`, and `hold:`.
3. With empty SMS text, the plugin applied a **single hard-coded overdue fallback** for every notice type (including HOLD).

### Fix (v1.2.3)

- **Normalize** single-line Koha YAML into valid multi-line YAML before parsing.
- **Recover** `sms.text` / `call.script` / `hold:` from inline content when parsing still fails (with log warning).
- **Log** YAML parse errors with `message_id`.
- **Letter-aware fallback** when text is still blank: HOLD, ODUE/DUE, PREDUE, CHECKOUT/CHECKIN, and generic — overdue wording **only** for overdue notices.
- **Phone fallback** added (was empty before); tries Koha `letter` table template first.

### Install

Download `koha-plugin-cirriusimpact-v1.2.3.kpz` from this release, upload via **Koha Administration → Plugins**, confirm version **1.2.3**, reload plugins.

### Verify

For a HOLD SMS notice, `messageText` should match the Koha notice script (or HOLD-specific fallback), not overdue text. For HOLD phone, `messageText` should contain the call script.
