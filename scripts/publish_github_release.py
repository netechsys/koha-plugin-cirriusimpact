#!/usr/bin/env python3
"""Publish a release tag to public GitHub (production mirror).

GitLab (origin) = private Devel. GitHub (github) = public releases only.
Requires GITHUB_TOKEN (repo scope) or SSH key authorized on netechsys/koha-plugin-cirriusimpact.

Usage:
  export GITHUB_TOKEN=ghp_...
  python3 scripts/publish_github_release.py v1.2.2

Or after manual: git push github v1.2.2
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

PLUGIN_ROOT = Path(__file__).resolve().parents[1]
GITHUB_REPO = "netechsys/koha-plugin-cirriusimpact"
GITHUB_URL = f"https://github.com/{GITHUB_REPO}"
TOKEN = os.getenv("GITHUB_TOKEN") or os.getenv("GH_TOKEN")


def _run(cmd: list[str], cwd: Path) -> None:
    print("+", " ".join(cmd))
    subprocess.run(cmd, cwd=cwd, check=True)


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


def _upload_release_asset(upload_url: str, kpz: Path) -> None:
    # upload_url template ends with {?name,label}
    url = upload_url.split("{", 1)[0] + f"?name={kpz.name}"
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

    main_pm = PLUGIN_ROOT / "Koha/Plugin/Com/CirriusImpact.pm"
    version = re.search(r'our \$VERSION\s*=\s*"([^"]+)"', main_pm.read_text()).group(1)
    if version != bare:
        print(f"Warning: tag {tag} != CirriusImpact.pm version {version}", file=sys.stderr)

    _run(["python3", "scripts/build_kpz.py"], PLUGIN_ROOT)
    kpz = PLUGIN_ROOT / f"koha-plugin-cirriusimpact-v{bare}.kpz"
    if not kpz.is_file():
        print(f"Missing {kpz}", file=sys.stderr)
        return 1

    # Push tag to GitHub (SSH remote). Fails if no github remote or no SSH auth.
    try:
        _run(["git", "push", "github", tag, "--force"], PLUGIN_ROOT)
    except subprocess.CalledProcessError as e:
        print(
            "git push github failed — add SSH deploy key or run manually:\n"
            f"  cd '{PLUGIN_ROOT}' && git push github {tag}",
            file=sys.stderr,
        )
        if not TOKEN:
            return e.returncode or 1

    if not TOKEN:
        print("GITHUB_TOKEN not set — tag push attempted; create GitHub Release manually.")
        print(f"{GITHUB_URL}/releases/new?tag={tag}")
        return 0

    notes_path = PLUGIN_ROOT / f"Koha/Plugin/Com/CirriusImpact/CirriusImpact/RELEASE_NOTES_v{bare}.md"
    body = notes_path.read_text() if notes_path.is_file() else f"Release {tag}"

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
    if code == 422 and isinstance(resp, dict) and "already_exists" in str(resp):
        # fetch existing release
        code2, resp2 = _github_request("GET", f"/repos/{GITHUB_REPO}/releases/tags/{tag}")
        if code2 != 200:
            print(f"Release exists but fetch failed: {resp2}", file=sys.stderr)
            return 1
        resp = resp2
    elif code not in (200, 201):
        print(f"GitHub release create failed {code}: {resp}", file=sys.stderr)
        return 1

    upload_url = resp.get("upload_url", "")
    if upload_url:
        _upload_release_asset(upload_url, kpz)

    html_url = resp.get("html_url", f"{GITHUB_URL}/releases/tag/{tag}")
    print(f"GitHub release published: {html_url}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
