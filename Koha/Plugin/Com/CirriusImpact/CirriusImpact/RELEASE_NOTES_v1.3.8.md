# CirriusImpact Koha Plugin v1.3.8

**Release date:** 2026-10-15

**GitLab:** https://smsgit2.cgsis.com/tcr/koha-plugin-cirriusimpact/-/releases/v1.3.8
**GitHub:** https://github.com/netechsys/koha-plugin-cirriusimpact/releases/tag/v1.3.8

## Summary

Configure Save works, claim stays on the public portal, and the notice installer no longer breaks Koha’s letter names or incremental CHECKOUT / CHECKIN / RENEWAL notices.

## Changes

- **Save.** Install templates is no longer nested inside the Save form, so **Include messageText** and the other feature fields submit when you click Save.
- **Claim URL.** A Bootstrap API URL of `127.0.0.1` or `localhost` is ignored. The claim target stays `https://configportal.cgsis.com/koha-bootstrap/v1/claim`.
- **messageText.** The column is filled unless you uncheck **Include messageText** and Save. The CSV sentence is the SMS or phone text from Koha’s queue. `{{ ci.titles }}` and `{{ ci.due }}` are filled at export.
- **letter.name.** Installing or wrapping a notice no longer renames it. Every transport of a letter code keeps one name, so the Notices screen stays consistent.
- **New transports.** A letter code that has email but no SMS row gets the canned SMS template instead of being skipped.
- **Incremental notices.** CHECKOUT, CHECKIN, RENEWAL, and HOLDDGST wraps keep the `----` repeat outside the sentence. The patron id is `[% borrower.borrowernumber %]`. RENEWAL repeats `[% checkout.issue_id %]`, the same checkout object Koha passes for CHECKOUT.
- **Copy templates.** Configure shows CHECKOUT, CHECKIN, and RENEWAL samples you can paste into Notices.

## Upgrade

1. Upload `koha-plugin-cirriusimpact-v1.3.8.kpz` via **Koha Administration → Plugins**.
2. Open **Configure**. Leave **Bootstrap API URL** at `https://configportal.cgsis.com/koha-bootstrap/v1/claim`.
3. **Save** once so Message Text is stored. It is on unless you uncheck it.
4. Re-run **Install notice templates** only if you want missing SMS/phone rows created or a stock CHECKOUT / CHECKIN / RENEWAL rebuilt. Notices that already contain `CirriusImpact: yes` are left as they are.
5. Replace any CHECKOUT or RENEWAL whose `----` lines sit inside the SMS quotes. Use the samples on Configure.

## CHECKOUT SMS

```yaml
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "The following items have been checked out: {{ ci.titles }}. Due {{ ci.due }}. Thank you for visiting [% branch.branchname %]."
checkouts:
----
  - [% checkout.issue_id %]
----
---
```

CHECKIN uses `old_checkouts:` and `[% old_checkout.issue_id %]`. RENEWAL uses the same `checkouts:` block as CHECKOUT.
