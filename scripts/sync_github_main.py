#!/usr/bin/env python3
"""Publish a squashed public snapshot to GitHub main (no co-author trailers).

GitHub is the public mirror. This script builds one clean commit from the
current working tree using git commit-tree (avoids IDE-injected Co-authored-by
trailers) and force-pushes main.

Usage:
  python3 scripts/sync_github_main.py
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
import urllib.parse
from pathlib import Path

PLUGIN_ROOT = Path(__file__).resolve().parents[1]
GITHUB_REPO = "netechsys/koha-plugin-cirriusimpact"
GITHUB_AUTHOR_NAME = "Terry Rossio"
GITHUB_AUTHOR_EMAIL = "18508581+netechsys@users.noreply.github.com"
MAIN_PM = PLUGIN_ROOT / "Koha/Plugin/Com/CirriusImpact.pm"


def _load_token() -> str:
    token = os.getenv("GITHUB_TOKEN") or os.getenv("GH_TOKEN")
    if token:
        return token
    path = Path.home() / ".multiserver_gitlab_env"
    if path.is_file():
        for line in path.read_text().splitlines():
            m = re.match(r'export GITHUB_TOKEN="([^"]+)"', line.strip())
            if m:
                return m.group(1)
    return ""


def _plugin_version() -> str:
    text = MAIN_PM.read_text()
    m = re.search(r'our \$VERSION\s*=\s*"([^"]+)"', text)
    return m.group(1) if m else "unknown"


def _squash_commit() -> str:
    env = os.environ.copy()
    env.setdefault("GIT_AUTHOR_NAME", GITHUB_AUTHOR_NAME)
    env.setdefault("GIT_AUTHOR_EMAIL", GITHUB_AUTHOR_EMAIL)
    env.setdefault("GIT_COMMITTER_NAME", env["GIT_AUTHOR_NAME"])
    env.setdefault("GIT_COMMITTER_EMAIL", env["GIT_AUTHOR_EMAIL"])
    version = _plugin_version()
    message = (
        f"CirriusImpact Koha plugin v{version}\n\n"
        "Public snapshot of the CirriusImpact Koha plugin source and docs."
    )
    tree = subprocess.check_output(["git", "write-tree"], cwd=PLUGIN_ROOT, text=True, env=env).strip()
    commit = subprocess.check_output(
        ["git", "commit-tree", tree, "-m", message],
        cwd=PLUGIN_ROOT,
        text=True,
        env=env,
    ).strip()
    if "Co-authored-by:" in subprocess.check_output(
        ["git", "log", "-1", "--format=%B", commit], cwd=PLUGIN_ROOT, text=True
    ):
        raise RuntimeError("Squash commit unexpectedly contains Co-authored-by trailer")
    return commit


def main() -> int:
    token = _load_token()
    if not token:
        print("Error: GITHUB_TOKEN required", file=sys.stderr)
        return 1
    commit = _squash_commit()
    push_url = (
        f"https://x-access-token:{urllib.parse.quote(token, safe='')}"
        f"@github.com/{GITHUB_REPO}.git"
    )
    env = os.environ.copy()
    env["GIT_TERMINAL_PROMPT"] = "0"
    cmd = ["git", "push", push_url, f"{commit}:refs/heads/main", "--force"]
    print("+ git push <github> <squash>:main --force")
    subprocess.run(cmd, cwd=PLUGIN_ROOT, check=True, env=env)
    print(f"Published squashed main ({commit[:8]}) to https://github.com/{GITHUB_REPO}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
