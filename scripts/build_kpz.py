#!/usr/bin/env python3
"""Build koha-plugin-cirriusimpact-v{VERSION}.kpz from Devel CI Plugin/Koha tree."""
import os
import re
import sys
import zipfile
from pathlib import Path

PLUGIN_ROOT = Path(__file__).resolve().parents[1]
KOHA_ROOT = PLUGIN_ROOT / "Koha"
MAIN_PM = KOHA_ROOT / "Plugin" / "Com" / "CirriusImpact.pm"


def main() -> int:
    if not MAIN_PM.is_file():
        print(f"Missing {MAIN_PM}", file=sys.stderr)
        return 1
    version = re.search(r'our \$VERSION\s*=\s*"([^"]+)"', MAIN_PM.read_text()).group(1)
    out = PLUGIN_ROOT / f"koha-plugin-cirriusimpact-v{version}.kpz"

    files: list[tuple[Path, str]] = []
    for root, _, names in os.walk(KOHA_ROOT):
        for name in names:
            full = Path(root) / name
            arc = str(full.relative_to(PLUGIN_ROOT)).replace(os.sep, "/")
            files.append((full, arc))

    dirs: set[str] = set()
    for _, arc in files:
        parts = arc.split("/")
        for i in range(1, len(parts)):
            dirs.add("/".join(parts[:i]) + "/")

    if out.exists():
        out.unlink()
    with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for d in sorted(dirs):
            zf.writestr(d, "")
        for full, arc in sorted(files, key=lambda x: x[1]):
            zf.write(full, arc)

    print(f"Built {out} ({out.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
