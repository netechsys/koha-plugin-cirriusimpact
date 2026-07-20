# CirriusImpact Koha Plugin — Bootstrap / onboarding track

This is a **development copy** of the CirriusImpact Koha plugin for work on
automated onboarding (claim token → SFTP + features), separate from the
**production v1.2.4** tree in `../CI Plugin`.

| Tree | Version | Purpose |
|------|---------|---------|
| `CI Plugin` | 1.2.4 | Production releases (GitLab/GitHub) |
| `CI Plugin Bootstrap` | 1.3.0-dev | Bootstrap API / Configure claim UI |
| `KohaBootstrap/` | — | Public claim service (isolated token DB) |

Do **not** publish KPZs from this tree to the v1.2.4 release channel until
intentionally versioned and reviewed.

## End-to-end claim flow

1. Portal approves a **Koha** draft (or admin clicks **Re-issue Koha install token**).
2. Portal calls claim service `POST /v1/admin/tokens` and emails the plaintext token
   (token only — no SFTP password).
3. Staff installs the plugin KPZ and opens **Configure → Claim configuration**.
4. Plugin `POST`s `{ library_id, token }` to the public claim URL.
5. Claim service validates the token in `KohaBootstrap` DB, then calls Portal
   `GET /api/internal/koha-bootstrap/<library>` for hostname / Librayuser / LibraryKey /
   feature flags.
6. Plugin stores host, username, password, and enable_* flags.

Templates stay **CLI-only** (`install_message_templates.pl`).

## In scope (bootstrap track)

- Separate public onboarding URL/API (not production portal APIs) — **done** (`../KohaBootstrap`)
- Configure UI: claim / re-claim install token — **done**
- Apply SFTP host/user/pass + feature flags from bootstrap payload — **done**
- Portal: generate / re-claim token and email to user — **done**
- **Branch enablement** (interim consortia): Configure checkboxes filter
  which patron home libraries are exported over the single SFTP claim — **done**

## Branch enablement (implemented)

- Configure → **Branches**: one checkbox per Koha library
- Filter key: patron **home** `branchcode` (same value as CSV `branch`)
- Storage (`enabled_branches` plugin data):
  - unset or `*` — no filter (all branches; upgrade-safe default)
  - comma list — only those codes
  - empty — export nothing
- Notices for disabled branches stay **`pending`** (not claimed/deleted)

## Claim UI (Configure)

- Bootstrap API URL (default `https://configportal-devel.cgsis.com/koha-bootstrap/v1/claim`)
- Library ID + install token → **Claim / Re-claim**
- On success: Connection + Features fields updated; `bootstrap_claimed_at` shown

## Portal env

```
KOHA_BOOTSTRAP_SERVICE_KEY=<shared with KohaBootstrap SERVICE_KEY>
KOHA_BOOTSTRAP_CLAIM_URL=http://127.0.0.1:6325
```

See `../Portal/koha_bootstrap.env.example` and `../KohaBootstrap/README.md`.

## Out of scope (for now)

- Auto-running `install_message_templates.pl` from the plugin
- Air-gapped / offline install path
- Per-branch FTP/keyword (still one claim / one SFTP per Koha instance)
- Filtering by hold pickup / owning branch (home library only for now)
- Production DNS/TLS cutover for the claim hostname

## Branch sync to Configuration Portal

On **Save**, enabled branch codes are POSTed to the claim service
`/v1/sync-branches` (using a sync token issued at claim time), which stores
`KOHA_ENABLED_BRANCHES` in ConfigurationDB via the Portal internal API.

Re-claim if Save reports that no sync token is present.
