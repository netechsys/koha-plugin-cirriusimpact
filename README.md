# koha-plugin-cirriusimpact

CirriusImpact Koha plugin — exports patron notices to CSV for Polaris SMS/Voice (shared with Koha / ByWater).

**Canonical source:** this repository (`Devel/Management/CI Plugin` on the management server).

**GitLab:** https://smsgit2.cgsis.com/tcr/koha-plugin-cirriusimpact

## Build install package

```bash
python3 scripts/build_kpz.py
```

Produces `koha-plugin-cirriusimpact-v{VERSION}.kpz` at the repo root (version from `Koha/Plugin/Com/CirriusImpact.pm`).

## Install on Koha

1. **Koha Administration → Plugins → Upload** the `.kpz`, or extract under the instance plugins directory.
2. Reload: `sudo koha-shell <instance> -c "perl -MKoha::Plugin -e 'Koha::Plugins->reload'"`

See `Koha/Plugin/Com/CirriusImpact/CirriusImpact/INSTALL.md` and `QUICKSTART.md`.

## Releases

Tagged releases and `.kpz` assets are published on the [GitLab releases page](https://smsgit2.cgsis.com/tcr/koha-plugin-cirriusimpact/-/releases).

```bash
python3 scripts/create_gitlab_release.py v1.2.2
```
