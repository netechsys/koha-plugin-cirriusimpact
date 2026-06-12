# koha-plugin-cirriusimpact

CirriusImpact Koha plugin — exports patron notices to CSV for the CirriusImpact SMS/Voice service (shared with Koha / ByWater).

**Canonical source (private Devel):** GitLab — https://smsgit2.cgsis.com/tcr/koha-plugin-cirriusimpact

**Public releases (production):** GitHub — https://github.com/netechsys/koha-plugin-cirriusimpact

| Remote | Use |
|---|---|
| `origin` (GitLab) | Daily development, all commits on `main` |
| `github` | Public `main` (docs, issue templates) + release **tags** (e.g. `v1.2.2`) + `.kpz` |

## Support and troubleshooting (public)

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

## Releases

**Private (GitLab):** [GitLab releases](https://smsgit2.cgsis.com/tcr/koha-plugin-cirriusimpact/-/releases)

```bash
python3 scripts/create_gitlab_release.py v1.2.2
```

**Public (GitHub):** [GitHub releases](https://github.com/netechsys/koha-plugin-cirriusimpact/releases)

```bash
export GITHUB_TOKEN=ghp_...   # classic PAT with repo scope (or fine-grained: contents + releases)
python3 scripts/publish_github_release.py v1.2.2
```

The script pushes the tag over **HTTPS using the token** (SSH not required).

Sync public `main` (issue templates, CONTRIBUTING, docs):

```bash
python3 scripts/sync_github_main.py
```
