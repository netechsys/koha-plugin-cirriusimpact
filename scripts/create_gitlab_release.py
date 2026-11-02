#!/usr/bin/env python3
"""Create GitLab release for koha-plugin-cirriusimpact with .kpz asset."""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

PLUGIN_ROOT = Path(__file__).resolve().parents[1]
TOKEN = os.getenv("GITLAB_TOKEN") or os.getenv("GLPAT")
GITLAB_URL = (os.getenv("GITLAB_URL") or "").rstrip("/")
PROJECT = os.getenv("GITLAB_PROJECT", "tcr/koha-plugin-cirriusimpact")
PROJECT_ID = int(os.getenv("GITLAB_PROJECT_ID", "10"))


def _request(method: str, url: str, body: dict | None = None, headers: dict | None = None) -> tuple[int, str]:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("PRIVATE-TOKEN", TOKEN)
    if body is not None:
        req.add_header("Content-Type", "application/json")
    if headers:
        for k, v in headers.items():
            req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return resp.status, resp.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def _upload_kpz(kpz_path: Path) -> str:
    boundary = "----CirriusImpactKpzBoundary"
    file_bytes = kpz_path.read_bytes()
    body = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="file"; filename="{kpz_path.name}"\r\n'
        f"Content-Type: application/octet-stream\r\n\r\n"
    ).encode() + file_bytes + f"\r\n--{boundary}--\r\n".encode()
    url = f"{GITLAB_URL}/api/v4/projects/{PROJECT_ID}/uploads"
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("PRIVATE-TOKEN", TOKEN)
    req.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")
    with urllib.request.urlopen(req, timeout=120) as resp:
        payload = json.loads(resp.read().decode())
    full_path = payload.get("full_path") or payload.get("url", "")
    if full_path.startswith("http"):
        return full_path
    return f"{GITLAB_URL}{full_path}"


def main() -> int:
    if not TOKEN:
        print("Error: set GITLAB_TOKEN", file=sys.stderr)
        return 1
    if not GITLAB_URL:
        print("Error: set GITLAB_URL (private GitLab base URL)", file=sys.stderr)
        return 1
    version = sys.argv[1] if len(sys.argv) > 1 else ""
    if not version:
        print("Usage: create_gitlab_release.py v1.2.2", file=sys.stderr)
        return 1
    tag = version if version.startswith("v") else f"v{version}"
    bare = tag.lstrip("v")
    kpz = PLUGIN_ROOT / f"koha-plugin-cirriusimpact-v{bare}.kpz"
    if not kpz.is_file():
        print(f"Missing {kpz}; run scripts/build_kpz.py first", file=sys.stderr)
        return 1

    notes_path = PLUGIN_ROOT / f"Koha/Plugin/Com/CirriusImpact/CirriusImpact/RELEASE_NOTES_v{bare}.md"
    if not notes_path.is_file():
        notes_path = PLUGIN_ROOT / f"Koha/Plugin/Com/CirriusImpact/CirriusImpact/RELEASE_NOTES_v{bare}.md"
    description = notes_path.read_text() if notes_path.is_file() else f"Release {tag}"

    print(f"Uploading {kpz.name}...")
    asset_url = _upload_kpz(kpz)
    print(f"Upload URL: {asset_url}")

    encoded = urllib.parse.quote(PROJECT, safe="")
    base = f"{GITLAB_URL}/api/v4/projects/{encoded}/releases"
    payload = {
        "name": f"Release {tag}",
        "tag_name": tag,
        "description": description,
        "assets": {
            "links": [
                {
                    "name": kpz.name,
                    "url": asset_url,
                    "link_type": "package",
                }
            ]
        },
    }
    code, raw = _request("POST", base, payload)
    if code in (200, 201):
        print(f"Created release {tag} for {PROJECT}")
        print(f"{GITLAB_URL}/{PROJECT}/-/releases/{tag}")
        return 0
    if code == 409:
        put_url = f"{base}/{tag}"
        code2, raw2 = _request("PUT", put_url, payload)
        if code2 in (200, 201):
            print(f"Updated release {tag} for {PROJECT}")
            print(f"{GITLAB_URL}/{PROJECT}/-/releases/{tag}")
            return 0
        print(f"Update failed {code2}: {raw2}", file=sys.stderr)
        return 1
    print(f"Create failed {code}: {raw}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
