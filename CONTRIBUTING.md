# Contributing

Thank you for helping improve the CirriusImpact Koha plugin.

## Where to report issues

| Channel | Use for |
|---|---|
| [GitHub Issues](https://github.com/netechsys/koha-plugin-cirriusimpact/issues) | Public bugs, feature requests, integration questions |
| [GitHub Discussions](https://github.com/netechsys/koha-plugin-cirriusimpact/discussions) | Troubleshooting, how-to questions, community Q&A |
| [GitHub Wiki](https://github.com/netechsys/koha-plugin-cirriusimpact/wiki) | Shared notes, library-specific tips (editable by maintainers) |

## Development

If you are a CirriusImpact developer with repository access:

1. Work on `main`
2. Build: `python3 scripts/build_kpz.py`
3. Publish public release: `python3 scripts/publish_github_release.py vX.Y.Z`

## Pull requests

This repository accepts PRs for:

- Documentation fixes
- Issue template improvements
- Release notes and install guides

Core plugin changes are merged by maintainers and included in the next tagged release.

## Security

See [SECURITY.md](SECURITY.md). Do not post credentials, SFTP passwords, or patron PII in issues.
