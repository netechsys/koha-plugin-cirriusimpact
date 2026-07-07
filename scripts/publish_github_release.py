#!/usr/bin/env python3
"""Publish a release tag to public GitHub (production mirror).

GitLab (origin) = private Devel. GitHub = public release tags + .kpz only.

Usage:
  export GITHUB_TOKEN=ghp_...
  python3 scripts/publish_github_release.py v1.2.2

Uses HTTPS + token for git push (no SSH key required).
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

PLUGIN_ROOT = Path(__file__).resolve().parents[1]
GITHUB_REPO = "netechsys/koha-plugin-cirriusimpact"
GITHUB_URL = f"https://github.com/{GITHUB_REPO}"
TOKEN = os.getenv("GITHUB_TOKEN") or os.getenv("GH_TOKEN")


def _load_token_from_env_files() -> str:
    """Load GITHUB_TOKEN from shell env files if not already exported."""
    if TOKEN:
        return TOKEN
    for path in (
        Path.home() / ".multiserver_gitlab_env",
        Path.home() / ".github_env",
    ):
        if not path.is_file():
            continue
        for line in path.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            for key in ("GITHUB_TOKEN", "GH_TOKEN"):
                m = re.match(rf'export\s+{key}="([^"]+)"', line)
                if m:
                    return m.group(1)
                m = re.match(rf"export\s+{key}=([^\s#]+)", line)
                if m:
                    return m.group(1).strip("'\"")
    return ""


TOKEN = _load_token_from_env_files() or TOKEN


def _run(cmd: list[str], cwd: Path, env: dict | None = None) -> None:
    print("+", " ".join(cmd))
    subprocess.run(cmd, cwd=cwd, check=True, env=env)


def _github_request(method: str, path: str, body: dict | None = None) -> tuple[int, dict | str]:
    url = f"https://api.github.com{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {TOKEN}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    if body is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            raw = resp.read().decode()
            try:
                return resp.status, json.loads(raw)
            except json.JSONDecodeError:
                return resp.status, raw
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except json.JSONDecodeError:
            return e.code, raw


def _push_tag_with_token(tag: str) -> None:
    """Push annotated tag to GitHub over HTTPS using GITHUB_TOKEN."""
    sha = subprocess.check_output(
        ["git", "rev-parse", tag],
        cwd=PLUGIN_ROOT,
        text=True,
    ).strip()
    push_url = f"https://x-access-token:{urllib.parse.quote(TOKEN, safe='')}@github.com/{GITHUB_REPO}.git"
    env = os.environ.copy()
    env["GIT_TERMINAL_PROMPT"] = "0"
    # Push tag ref; force so retagged v1.2.2 can be updated
    _run(["git", "push", push_url, f"refs/tags/{tag}:refs/tags/{tag}", "--force"], PLUGIN_ROOT, env=env)
    print(f"Pushed tag {tag} ({sha[:8]}) to GitHub")


def _ensure_tag_on_github(tag: str) -> None:
    """Create or update tag on GitHub via API if git push is unavailable."""
    sha = subprocess.check_output(
        ["git", "rev-parse", tag],
        cwd=PLUGIN_ROOT,
        text=True,
    ).strip()
    ref = f"tags/{tag}"
    code, resp = _github_request("GET", f"/repos/{GITHUB_REPO}/git/ref/{urllib.parse.quote(ref, safe='')}")
    if code == 200:
        _github_request("PATCH", f"/repos/{GITHUB_REPO}/git/refs/{urllib.parse.quote(ref, safe='')}", {"sha": sha, "force": True})
        print(f"Updated GitHub tag {tag} -> {sha[:8]}")
        return
    if code != 404:
        print(f"Warning: could not read tag ref ({code}): {resp}", file=sys.stderr)
    code2, resp2 = _github_request(
        "POST",
        f"/repos/{GITHUB_REPO}/git/refs",
        {"ref": f"refs/tags/{tag}", "sha": sha},
    )
    if code2 in (200, 201):
        print(f"Created GitHub tag {tag} -> {sha[:8]}")
        return
    if code2 == 422:
        _github_request("PATCH", f"/repos/{GITHUB_REPO}/git/refs/{urllib.parse.quote(ref, safe='')}", {"sha": sha, "force": True})
        print(f"Force-updated GitHub tag {tag} -> {sha[:8]}")
        return
    raise RuntimeError(f"Failed to create tag on GitHub ({code2}): {resp2}")


def _get_release_by_tag(tag: str) -> dict | None:
    code, resp = _github_request("GET", f"/repos/{GITHUB_REPO}/releases/tags/{tag}")
    if code == 200 and isinstance(resp, dict):
        return resp
    return None


def _delete_release_assets(release: dict) -> None:
    for asset in release.get("assets", []) or []:
        aid = asset.get("id")
        if aid:
            _github_request("DELETE", f"/repos/{GITHUB_REPO}/releases/assets/{aid}")


def _upload_release_asset(upload_url: str, kpz: Path) -> None:
    url = upload_url.split("{", 1)[0] + f"?name={urllib.parse.quote(kpz.name)}"
    file_bytes = kpz.read_bytes()
    req = urllib.request.Request(url, data=file_bytes, method="POST")
    req.add_header("Authorization", f"Bearer {TOKEN}")
    req.add_header("Content-Type", "application/octet-stream")
    req.add_header("Accept", "application/vnd.github+json")
    with urllib.request.urlopen(req, timeout=300) as resp:
        print(f"Uploaded asset {kpz.name} (HTTP {resp.status})")


def main() -> int:
    tag = sys.argv[1] if len(sys.argv) > 1 else ""
    if not tag:
        print("Usage: publish_github_release.py v1.2.2", file=sys.stderr)
        return 1
    if not tag.startswith("v"):
        tag = f"v{tag}"
    bare = tag.lstrip("v")

    if not TOKEN:
        print(
            "Error: set GITHUB_TOKEN (classic PAT with repo scope).\n"
            "  export GITHUB_TOKEN=ghp_...\n"
            "  or add to ~/.multiserver_gitlab_env:\n"
            '    export GITHUB_TOKEN="ghp_..."',
            file=sys.stderr,
        )
        return 1

    main_pm = PLUGIN_ROOT / "Koha/Plugin/Com/CirriusImpact.pm"
    version = re.search(r'our \$VERSION\s*=\s*"([^"]+)"', main_pm.read_text()).group(1)
    if version != bare:
        print(f"Warning: tag {tag} != CirriusImpact.pm version {version}", file=sys.stderr)

    _run(["python3", "scripts/build_kpz.py"], PLUGIN_ROOT)
    kpz = PLUGIN_ROOT / f"koha-plugin-cirriusimpact-v{bare}.kpz"
    if not kpz.is_file():
        print(f"Missing {kpz}", file=sys.stderr)
        return 1

    # Push tag to GitHub (HTTPS + token — not SSH)
    try:
        _push_tag_with_token(tag)
    except subprocess.CalledProcessError:
        print("HTTPS git push failed; trying GitHub API tag create/update...", file=sys.stderr)
        try:
            _ensure_tag_on_github(tag)
        except Exception as e:
            print(f"Error: could not publish tag to GitHub: {e}", file=sys.stderr)
            return 1

    notes_path = PLUGIN_ROOT / f"Koha/Plugin/Com/CirriusImpact/CirriusImpact/RELEASE_NOTES_v{bare}.md"
    body = notes_path.read_text() if notes_path.is_file() else f"Release {tag}"

    existing = _get_release_by_tag(tag)
    if existing:
        rid = existing["id"]
        code, resp = _github_request(
            "PATCH",
            f"/repos/{GITHUB_REPO}/releases/{rid}",
            {"name": f"Release {tag}", "body": body},
        )
        if code not in (200, 201):
            print(f"GitHub release update failed {code}: {resp}", file=sys.stderr)
            return 1
        release = resp if isinstance(resp, dict) else existing
        _delete_release_assets(release)
        print(f"Updated existing GitHub release {tag}")
    else:
        code, resp = _github_request(
            "POST",
            f"/repos/{GITHUB_REPO}/releases",
            {
                "tag_name": tag,
                "name": f"Release {tag}",
                "body": body,
                "draft": False,
                "prerelease": False,
            },
        )
        if code not in (200, 201):
            print(f"GitHub release create failed {code}: {resp}", file=sys.stderr)
            return 1
        release = resp

    upload_url = release.get("upload_url", "") if isinstance(release, dict) else ""
    if upload_url:
        _upload_release_asset(upload_url, kpz)

    html_url = release.get("html_url", f"{GITHUB_URL}/releases/tag/{tag}") if isinstance(release, dict) else f"{GITHUB_URL}/releases/tag/{tag}"
    print(f"GitHub release published: {html_url}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
