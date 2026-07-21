# CirriusImpact Koha Plugin — Supported Notice Types

**Document date:** June 17, 2026  
**Plugin release:** CirriusImpact **v1.2.2**  
**Releases:** https://github.com/netechsys/koha-plugin-cirriusimpact/releases  
**Integration:** SMS (`commType=T`) and voice (`commType=V`) via CSV export + SFTP; Koha status lifecycle (`pending` → `transmitted` → `sent` / `failed` / `pending`)

---

## Purpose

This document lists Koha **letter codes** that the CirriusImpact plugin exports with valid **`notificationType`** and **`notificationLevel`** fields, so the CirriusImpact notification service accepts the CSV and can deliver SMS/voice notices and report results back to Koha.

A notice is **fully supported** when:

1. The plugin **`before_send_messages`** hook selects it (installed template with `CirriusImpact: yes`),
2. **`notification_mapping.yml`** maps the Koha letter code to CirriusImpact type/level, and
3. CirriusImpact validates `notificationType` as `1`–`6` (or library-configured extensions).

---

## CirriusImpact notification type categories

| `notificationType` | Category | Typical Koha use |
|---------------------|----------|------------------|
| **1** | Overdue | ODUE, ODUE2, ODUE3, DUE, DUEDGST |
| **2** | Hold | HOLD, HOLDDGST, hold placed/changed/reminder, hold slip |
| **3** | Circulation | CHECKOUT, CHECKIN |
| **4** | Pre-due | PREDUE, PREDUEDGST |
| **5** | Renewal | RENEWAL, AUTO_RENEWALS, AUTO_RENEWALS_DGST |
| **6** | Membership / account | MEMBERSHIP_EXPIRY, MEMBERSHIP_RENEWED, WELCOME |

Each CSV row also carries **`notificationLevel`** (`1`–`6`) for escalation within that type.

---

## Fully supported notice codes (v1.2.2)

### Type 1 — Overdue

| Koha letter code | Type | Level | Description |
|------------------|------|-------|-------------|
| **ODUE** | 1 | 1 | First overdue notice |
| **ODUE2** | 1 | 2 | Second overdue notice |
| **ODUE3** | 1 | 3 | Third overdue notice |
| **DUE** | 1 | 4 | Overdue notice (custom letter code, e.g. site-specific `overduerules`) |
| **DUEDGST** | 1 | 4 | Overdue digest (if configured at a site) |

**Note:** The plugin also loads **any** letter configured in Koha `overduerules` (`letter1` / `letter2` / `letter3`). Only codes listed above (or added to `notification_mapping.yml`) export with a valid `notificationType`. Unmapped overdue letters are exported with a blank `notificationType` and **rejected by CirriusImpact**.

---

### Type 2 — Hold

| Koha letter code | Type | Level | Description |
|------------------|------|-------|-------------|
| **HOLD** | 2 | 1 | Item ready for pickup (single hold) |
| **HOLDDGST** | 2 | 1 | Hold available (digest) |
| **HOLD_CHANGED** | 2 | 2 | Hold status changed |
| **HOLD_REMINDER** | 2 | 3 | Hold reminder |
| **HOLDPLACED** | 2 | 4 | Hold placed confirmation |
| **HOLDPLACED_PATRON** | 2 | 5 | Hold placed confirmation (patron) |
| **HOLD_SLIP** | 2 | 6 | Hold slip (email transport in Koha; included in pipeline) |

**CirriusImpact behavior:** `HOLD` and `*DGST` hold types are **not rolled up** — each Koha row can become its own SMS/voice when appropriate.

---

### Type 3 — Circulation

| Koha letter code | Type | Level | Description |
|------------------|------|-------|-------------|
| **CHECKOUT** | 3 | 1 | Item checked out |
| **CHECKIN** | 3 | 2 | Item checked in |

---

### Type 4 — Pre-due

| Koha letter code | Type | Level | Description |
|------------------|------|-------|-------------|
| **PREDUE** | 4 | 1 | Pre-due reminder (single item) |
| **PREDUEDGST** | 4 | 1 | Pre-due reminder (digest) |

**CirriusImpact behavior:** `*DGST` pre-due types are **not rolled up** (Koha already consolidates digest rows).

**Plugin behavior (v1.2.2):** Multi-item PREDUE exports match `itemsID` / `title` to each row’s `messageText`.

---

### Type 5 — Renewal

| Koha letter code | Type | Level | Description |
|------------------|------|-------|-------------|
| **RENEWAL** | 5 | 1 | Manual renewal confirmation |
| **AUTO_RENEWALS** | 5 | 2 | Auto-renewal notification |
| **AUTO_RENEWALS_DGST** | 5 | 2 | Auto-renewal notification (digest) |

---

### Type 6 — Membership / account

| Koha letter code | Type | Level | Description |
|------------------|------|-------|-------------|
| **MEMBERSHIP_EXPIRY** | 6 | 1 | Membership expiring |
| **MEMBERSHIP_RENEWED** | 6 | 2 | Membership renewed |
| **WELCOME** | 6 | 3 | Welcome message |

---

## Summary count

| Category | Letter codes (fully mapped) |
|----------|----------------------------|
| Overdue | 5 |
| Hold | 7 |
| Circulation | 2 |
| Pre-due | 2 |
| Renewal | 3 |
| Membership | 3 |
| **Total** | **22** |

---

## Transport and pipeline requirements

For each notice to reach CirriusImpact:

| Requirement | Detail |
|-------------|--------|
| Koha template | Must include **`CirriusImpact: yes`** in notice content |
| Transports | SMS and/or phone templates as configured in Koha |
| CSV fields | Plugin populates `notificationType`, `notificationLevel`, `kohaNotificationType`, `messageText`, `TxnID` (message_queue id), patron/item fields |
| Delivery | CSV uploaded via plugin SFTP to the CirriusImpact service |
| Status API | CirriusImpact calls Koha REST `POST /api/v1/contrib/cirriusimpact/message/{id}/status` with `sent`, `failed`, or `pending` |
| ODUE phone suppression | Optional: skip voice ODUE when patron has SMS/email (plugin config) |

---

## Plugin-ready codes (exported but not yet in `notification_mapping.yml`)

These are in the plugin’s **`_hold_codes()`** pick-up list. If a library enables them **without** adding YAML entries, CirriusImpact will **reject** the CSV (blank `notificationType`).

| Koha letter code | Status |
|------------------|--------|
| HOLD_CHANGEDGST | Mapping not in YAML — add before use |
| HOLD_REMINDERGST | Mapping not in YAML — add before use |
| HOLDPLACEDGST | Mapping not in YAML — add before use |
| HOLDPLACED_PATRONGST | Mapping not in YAML — add before use |

---

## Approval checklist for ByWater

Please confirm:

- [ ] The **22 mapped letter codes** above match your expected Koha → CirriusImpact integration scope.
- [ ] **CirriusImpact notification types 1–6** align with your MessageBee / CirriusImpact notification model.
- [ ] **`DUE` / `DUEDGST` at type 1, level 4** is acceptable for sites that use non-standard overdue letter names.
- [ ] Hold digest variants (`*DGST`) and **HOLD** no-rollup behavior is acceptable.
- [ ] Any additional site-specific overdue letters should be added to **`notification_mapping.yml`** before production use.

---

## Reference files (v1.2.2)

| File | Role |
|------|------|
| `notification_mapping.yml` | Koha letter code → CirriusImpact type/level |
| `CirriusImpact.pm` → `before_send_messages` | Notice selection and CSV export |
| `NOTIFICATION_TYPES.md` | In-plugin documentation of mappings |
| `RELEASE_NOTES_v1.2.4.md` | Current production release notes |

---

**Install package:** `koha-plugin-cirriusimpact-v1.2.2.kpz` from [GitHub releases](https://github.com/netechsys/koha-plugin-cirriusimpact/releases)
