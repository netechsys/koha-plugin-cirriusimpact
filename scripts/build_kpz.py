#!/usr/bin/env python3
"""Build koha-plugin-cirriusimpact-v{VERSION}.kpz from Devel CI Plugin/Koha tree.

Koha uses Archive::Extract / Archive::Zip. Prefer Info-ZIP-style packages:
explicit directory entries stored (not deflated empty payloads), Unix attrs.
"""
import os
import re
import sys
import time
import zipfile
from pathlib import Path

PLUGIN_ROOT = Path(__file__).resolve().parents[1]
KOHA_ROOT = PLUGIN_ROOT / "Koha"
MAIN_PM = KOHA_ROOT / "Plugin" / "Com" / "CirriusImpact.pm"


def _dos_date(ts: float | None = None) -> tuple[int, int, int, int, int, int]:
    t = time.localtime(ts if ts is not None else time.time())
    return (t.tm_year, t.tm_mon, t.tm_mday, t.tm_hour, t.tm_min, t.tm_sec)


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
    with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED, allowZip64=False) as zf:
        for d in sorted(dirs):
            zi = zipfile.ZipInfo(d, date_time=_dos_date())
            zi.compress_type = zipfile.ZIP_STORED
            zi.create_system = 3  # Unix
            zi.external_attr = (0o40755 << 16) | 0x10  # dir + MS-DOS dir bit
            zf.writestr(zi, b"")
        for full, arc in sorted(files, key=lambda x: x[1]):
            zi = zipfile.ZipInfo(arc, date_time=_dos_date(full.stat().st_mtime))
            zi.compress_type = zipfile.ZIP_DEFLATED
            zi.create_system = 3
            mode = full.stat().st_mode & 0o777
            if mode & 0o111:
                zi.external_attr = (mode << 16)
            else:
                zi.external_attr = (0o644 << 16)
            zf.writestr(zi, full.read_bytes())

    print(f"Built {out} ({out.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
