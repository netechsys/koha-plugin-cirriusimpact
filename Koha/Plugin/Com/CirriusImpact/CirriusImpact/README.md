# CirriusImpact Koha Plugin

Version: **1.3.10**

Integrates Koha with CirriusImpact for SMS and voice patron notices (CSV export over SFTP).

## Docs

- [QUICKSTART.md](QUICKSTART.md) — get started after KPZ install
- [INSTALL.md](INSTALL.md) — install and configure
- [TEMPLATE_I18N.md](TEMPLATE_I18N.md) — multilingual notice templates (CLI)
- [NOTIFICATION_TYPES.md](NOTIFICATION_TYPES.md) — supported notice types
- [BYWATER_SUPPORTED_NOTICES.md](BYWATER_SUPPORTED_NOTICES.md) — ByWater-oriented notice list
- [CHANGELOG.md](CHANGELOG.md) — history
- [RELEASE_NOTES_v1.3.10.md](RELEASE_NOTES_v1.3.10.md) — current production release notes
- [RELEASE_NOTES_v1.3.9.md](RELEASE_NOTES_v1.3.9.md) — notice upgrade and comparison download
- [RELEASE_NOTES_v1.3.8.md](RELEASE_NOTES_v1.3.8.md) — Configure Save, letter names, incremental notices
- [RELEASE_NOTES_v1.3.7.md](RELEASE_NOTES_v1.3.7.md) — production claim URL
- [RELEASE_NOTES_v1.3.6.md](RELEASE_NOTES_v1.3.6.md) — notice dates

## Features (summary)

- CSV export for CirriusImpact (SMS / voice; `messageText` on by default)
- Multi-item notices: incremental CHECKOUT / CHECKIN / RENEWAL / HOLDDGST and all-at-once PREDUEDGST / DUEDGST / AUTO_RENEWALS_DGST / ODUE* send one message listing every item; plugin upgrade migrates untouched canned templates
- Notice dates follow Koha's `dateformat` preference (US `MM/DD/YYYY`, metric `DD/MM/YYYY`, …) on every notice; voice speaks the month name
- Configure: **Claim** install token, Connection (SFTP), **Branch services** matrix (SMS / CIXL / Outbound), Type 1 & Type 2 consortia
- Features: skip ODUE voice when SMS/email exists; include `messageText` in CSV
- REST callbacks for notice status (`sent` / `inprogress` / `failed`)
- CLI template installer (`install_message_templates.pl`) and **Configure → Install notice templates** — Defaults/Consortia **wrap** existing letter text; **Remove / revert** restores; `--ci-templates` installs canned CI Defaults on the normal notice's SMS and phone tabs

## Support

https://smsgit2.cgsis.com/tcr/koha-plugin-cirriusimpact/-/releases
