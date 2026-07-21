# CirriusImpact Koha plugin

Exports Koha patron notices for CirriusImpact SMS and voice delivery.

**Repository:** https://github.com/netechsys/koha-plugin-cirriusimpact

## Install packages

| Channel | Version | Package |
|---------|---------|---------|
| **Production (stable)** | **v1.2.4** | [koha-plugin-cirriusimpact-v1.2.4.kpz](https://github.com/netechsys/koha-plugin-cirriusimpact/releases/download/v1.2.4/koha-plugin-cirriusimpact-v1.2.4.kpz) |
| Lab / pre-release | v1.3.0-dev | See [Releases](https://github.com/netechsys/koha-plugin-cirriusimpact/releases) (prerelease) |

Use **v1.2.4** for production Koha sites unless CirriusImpact has asked you to test a pre-release.

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
2. Configure SFTP connection (or use Claim when CirriusImpact provides an install token)
3. Optionally run `install_message_templates.pl` via `koha-shell` (see TEMPLATE_I18N.md)

## Support

- Issues: https://github.com/netechsys/koha-plugin-cirriusimpact/issues
- Releases: https://github.com/netechsys/koha-plugin-cirriusimpact/releases
