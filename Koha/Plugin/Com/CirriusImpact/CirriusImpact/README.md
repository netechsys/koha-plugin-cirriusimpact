# CirriusImpact Koha Plugin

Version: **1.3.0-dev** (pre-release) · Production stable: **1.2.4**

Integrates Koha with CirriusImpact for SMS and voice patron notices (CSV export over SFTP).

## Docs

- [QUICKSTART.md](QUICKSTART.md) — get started after KPZ install
- [INSTALL.md](INSTALL.md) — install and configure
- [TEMPLATE_I18N.md](TEMPLATE_I18N.md) — multilingual notice templates (CLI)
- [NOTIFICATION_TYPES.md](NOTIFICATION_TYPES.md) — supported notice types
- [BYWATER_SUPPORTED_NOTICES.md](BYWATER_SUPPORTED_NOTICES.md) — ByWater-oriented notice list
- [CHANGELOG.md](CHANGELOG.md) — history
- [RELEASE_NOTES_v1.2.4.md](RELEASE_NOTES_v1.2.4.md) — current production release notes

## Features (summary)

- CSV export for CirriusImpact (SMS / voice; optional `messageText`)
- Configure: SFTP connection, SMS/phone enables, branch allowlist
- Claim / re-claim install token (when provided by CirriusImpact)
- REST callbacks for notice status (`sent` / `inprogress` / `failed`)
- CLI template installer (`install_message_templates.pl`) — not run automatically

## Support

https://github.com/netechsys/koha-plugin-cirriusimpact/issues
