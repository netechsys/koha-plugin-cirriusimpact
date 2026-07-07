# koha-plugin-cirriusimpact

CirriusImpact Koha plugin — exports patron notices to CSV for the CirriusImpact SMS/Voice service (shared with Koha / ByWater).

**Repository:** https://github.com/netechsys/koha-plugin-cirriusimpact

## Support and troubleshooting

| Resource | Link |
|---|---|
| **Issues** | https://github.com/netechsys/koha-plugin-cirriusimpact/issues |
| **Discussions** | https://github.com/netechsys/koha-plugin-cirriusimpact/discussions |
| **Wiki** | https://github.com/netechsys/koha-plugin-cirriusimpact/wiki |
| **Releases / .kpz** | https://github.com/netechsys/koha-plugin-cirriusimpact/releases |
| **Contributing** | [CONTRIBUTING.md](CONTRIBUTING.md) |

The repository is **public** — anyone can read source, open issues, and participate in discussions.

## Build install package

```bash
python3 scripts/build_kpz.py
```

Produces `koha-plugin-cirriusimpact-v{VERSION}.kpz` at the repo root (version from `Koha/Plugin/Com/CirriusImpact.pm`).

## Install on Koha

1. **Koha Administration → Plugins → Upload** the `.kpz`, or extract under the instance plugins directory.
2. Reload: `sudo koha-shell <instance> -c "perl -MKoha::Plugin -e 'Koha::Plugins->reload'"`

See `Koha/Plugin/Com/CirriusImpact/CirriusImpact/INSTALL.md` and `QUICKSTART.md`.
