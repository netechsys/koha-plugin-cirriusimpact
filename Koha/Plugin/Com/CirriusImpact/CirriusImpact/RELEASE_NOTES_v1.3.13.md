# CirriusImpact Koha Plugin v1.3.13

**Date:** 2026-11-02

**GitLab:** https://smsgit2.cgsis.com/tcr/koha-plugin-cirriusimpact/-/releases/v1.3.13
**GitHub:** https://github.com/netechsys/koha-plugin-cirriusimpact/releases/tag/v1.3.13

## Summary

Install notice templates now separates **what** is written from **where** it is written. Consortia branches can take the canned CI templates or keep the library's existing wording.

## What changed

- **What to install:** CI templates, or Library Existing.
- **Where:** system default (`branchcode=''`), every branch with a service enabled in Branch services, or the Koha branchcodes you select.
- CI templates on a branch writes the canned notice on that branch's normal letter (`CHECKOUT` at `CPL`, not a letter named `CHECKOUT-CPL`).
- Library Existing on a branch wraps the text already stored for that branch.
- Remove / revert uses the same two choices.
- Command line: add `--consortia-content=ci-templates` to `--consortia-branch` or `--consortia-from-plugin`. Without that flag, consortia still wraps.

## Upgrade

Upload `koha-plugin-cirriusimpact-v1.3.13.kpz` via **Koha Administration → Plugins**. Open Configure → Install notice templates. CI templates and System default are selected. Choose Consortia and Library Existing when a branch should keep its current wording.
