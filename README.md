# CirriusImpact Koha plugin

Exports Koha patron notices for CirriusImpact SMS and voice delivery.

**Private GitLab (current releases):** https://smsgit2.cgsis.com/tcr/koha-plugin-cirriusimpact  
**Public GitHub (mirror):** https://github.com/netechsys/koha-plugin-cirriusimpact

## Install packages

| Channel | Version | Package |
|---------|---------|---------|
| **Production (stable)** | **v1.3.1** | [koha-plugin-cirriusimpact-v1.3.1.kpz](https://smsgit2.cgsis.com/tcr/koha-plugin-cirriusimpact/-/releases/v1.3.1) |
| Previous | v1.2.4 | See [GitLab Releases](https://smsgit2.cgsis.com/tcr/koha-plugin-cirriusimpact/-/releases) |

Use **v1.3.1** for production Koha sites unless CirriusImpact specifies another build.

## Documentation

| Doc | Purpose |
|-----|---------|
| [QUICKSTART.md](Koha/Plugin/Com/CirriusImpact/CirriusImpact/QUICKSTART.md) | Fast path after KPZ install |
| [INSTALL.md](Koha/Plugin/Com/CirriusImpact/CirriusImpact/INSTALL.md) | Install and configure |
| [TEMPLATE_I18N.md](Koha/Plugin/Com/CirriusImpact/CirriusImpact/TEMPLATE_I18N.md) | Notice template installer (CLI) |
| [NOTIFICATION_TYPES.md](Koha/Plugin/Com/CirriusImpact/CirriusImpact/NOTIFICATION_TYPES.md) | Supported notice types |
| [CHANGELOG.md](Koha/Plugin/Com/CirriusImpact/CirriusImpact/CHANGELOG.md) | Version history |
| [SECURITY.md](SECURITY.md) | Security reporting |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Contributions |

## Build

```bash
python3 scripts/build_kpz.py
```

Produces `koha-plugin-cirriusimpact-v{VERSION}.kpz` (version from `Koha/Plugin/Com/CirriusImpact.pm`).

## Install on Koha

1. **Koha Administration → Plugins → Upload** the `.kpz`
2. **Configure → Claim** with Library ID + install token (fills SFTP), then set **Branch services** and **Save**
3. Run `install_message_templates.pl` via `koha-shell` (see [QUICKSTART.md](Koha/Plugin/Com/CirriusImpact/CirriusImpact/QUICKSTART.md) / [INSTALL.md](Koha/Plugin/Com/CirriusImpact/CirriusImpact/INSTALL.md))

## Support

- Releases (GitLab): https://smsgit2.cgsis.com/tcr/koha-plugin-cirriusimpact/-/releases
- Public issues (GitHub mirror): https://github.com/netechsys/koha-plugin-cirriusimpact/issues
