# Contributing

Thank you for helping improve the CirriusImpact Koha plugin.

## Where to report issues

| Channel | Use for |
|---|---|
| [GitHub Issues](https://github.com/netechsys/koha-plugin-cirriusimpact/issues) | Public bugs, feature requests, integration questions |
| [GitHub Discussions](https://github.com/netechsys/koha-plugin-cirriusimpact/discussions) | Troubleshooting, how-to questions, community Q&A |
| [GitHub Wiki](https://github.com/netechsys/koha-plugin-cirriusimpact/wiki) | Shared notes, library-specific tips (editable by maintainers) |

## Development source

Day-to-day development happens in a **private GitLab** repository. **Public GitHub** receives **release tags** and community documentation on `main`.

If you are a CirriusImpact developer:

1. Work on GitLab `main`
2. Build: `python3 scripts/build_kpz.py`
3. Publish public release: `python3 scripts/publish_github_release.py vX.Y.Z`
4. Sync community/docs to GitHub `main`: `python3 scripts/sync_github_main.py`

## Pull requests

This public repository accepts PRs for:

- Documentation fixes
- Issue template improvements
- Release notes and install guides

Core plugin changes are merged via the private GitLab workflow first, then included in the next tagged release.

## Security

See [SECURITY.md](SECURITY.md). Do not post credentials, SFTP passwords, or patron PII in issues.
