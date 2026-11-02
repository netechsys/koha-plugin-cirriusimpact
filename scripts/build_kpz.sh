#!/bin/bash
# Build Koha installable .kpz from Devel CI Plugin source (Koha/ subtree).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KOHA_ROOT="$PLUGIN_ROOT/Koha"
MAIN_PM="$KOHA_ROOT/Plugin/Com/CirriusImpact.pm"

if [[ ! -f "$MAIN_PM" ]]; then
  echo "Missing $MAIN_PM" >&2
  exit 1
fi

VERSION=$(grep -m1 'our \$VERSION' "$MAIN_PM" | sed 's/.*"\([^"]*\)".*/\1/')
OUT="$PLUGIN_ROOT/koha-plugin-cirriusimpact-v${VERSION}.kpz"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

python3 <<PY
import os, zipfile
from pathlib import Path

plugin_root = Path(${PLUGIN_ROOT@Q})
koha_root = plugin_root / "Koha"
out = plugin_root / f"koha-plugin-cirriusimpact-v${VERSION}.kpz"
staging = Path(${TMP@Q})

files = []
for root, _, names in os.walk(koha_root):
    for name in names:
        full = Path(root) / name
        arc = str(full.relative_to(plugin_root)).replace(os.sep, "/")
        files.append((full, arc))

dirs = set()
for _, arc in files:
    parts = arc.split("/")
    for i in range(1, len(parts)):
        dirs.add("/".join(parts[:i]) + "/")

with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for d in sorted(dirs):
        zf.writestr(d, "")
    for full, arc in sorted(files, key=lambda x: x[1]):
        zf.write(full, arc)

print(f"Built {out} ({out.stat().st_size} bytes)")
PY
