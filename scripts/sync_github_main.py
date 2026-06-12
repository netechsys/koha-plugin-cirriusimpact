#!/usr/bin/env python3
"""Push main branch to public GitHub (community docs, issue templates, source mirror).

Does not replace tag-based release publish; use after updating CONTRIBUTING,
.github templates, README, etc.

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


def main() -> int:
    token = _load_token()
    if not token:
        print("Error: GITHUB_TOKEN required", file=sys.stderr)
        return 1
    push_url = (
        f"https://x-access-token:{urllib.parse.quote(token, safe='')}"
        f"@github.com/{GITHUB_REPO}.git"
    )
    env = os.environ.copy()
    env["GIT_TERMINAL_PROMPT"] = "0"
    cmd = ["git", "push", push_url, "main:main", "--force"]
    print("+ git push <github> main:main")
    subprocess.run(cmd, cwd=PLUGIN_ROOT, check=True, env=env)
    print(f"Synced main to https://github.com/{GITHUB_REPO}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
