#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------
# CirriusImpact KPZ packer + version manager
# - Auto-bump patch:      ./make_kpz.sh bump
# - Set explicit version: ./make_kpz.sh 1.1.15
# - Add git tag:          ./make_kpz.sh --tag bump
# - Add tag & push:       GIT_PUSH=1 ./make_kpz.sh --tag 1.1.15
# - Also updates CHANGELOG.md and README.md on bump
# ------------------------------------------

# ---- config (adjust if layout differs) ----
PLUG_BASE="Koha/Plugin/Com/ByWaterSolutions"
PLUG_PERL="$PLUG_BASE/CirriusImpact.pm"
PLUG_DIR="$PLUG_BASE/CirriusImpact"

CHANGELOG="$PLUG_DIR/CHANGELOG.md"
README="$PLUG_DIR/README.md"

# ---- helper: usage ----
usage() {
  cat <<'EOF'
Usage:
  make_kpz.sh [--tag] [VERSION|bump]

Examples:
  make_kpz.sh                      # build KPZ using current version in CirriusImpact.pm
  make_kpz.sh 1.1.15               # set package name=1.1.15 (does NOT edit files)
  make_kpz.sh bump                 # bump patch in CirriusImpact.pm, then build
  make_kpz.sh --tag bump           # bump, update CHANGELOG/README, commit, tag vX.Y.Z
  GIT_PUSH=1 make_kpz.sh --tag 1.1.15   # tag v1.1.15 and git push --tags

Notes:
- "bump" edits CirriusImpact.pm and prepends a new section to CHANGELOG.md.
- README.md gets its first obvious version mention updated on bump.
- Use --tag to create a git commit (if bump) and an annotated tag "v<version>".
- Set GIT_PUSH=1 to push the tag and commit to origin.
EOF
}

# ---- parse flags ----
DO_TAG=0
ARGS=()
for a in "${@:-}"; do
  case "$a" in
    -h|--help) usage; exit 0;;
    --tag) DO_TAG=1;;
    *) ARGS+=("$a");;
  esac
done
set -- "${ARGS[@]:-}"

# ---- sanity checks ----
need() { [[ -e "$1" ]] || { echo "Missing: $1" >&2; exit 1; }; }
need "$PLUG_PERL"
need "$PLUG_DIR/API.pm"
need "$PLUG_DIR/configure.tt"
need "$PLUG_DIR/openapi.json"

# ---- read current version from .pm ----
CUR_VERSION="$(perl -ne 'print $1 and exit if /our\s+\$VERSION\s*=\s*"([^"]+)"/' "$PLUG_PERL" || true)"
if [[ -z "${CUR_VERSION}" ]]; then
  echo "Could not read version from $PLUG_PERL" >&2
  exit 1
fi

# ---- decide version ----
INPUT="${1:-}"
EDITED_FILE=0
DATE="$(date +%Y-%m-%d)"
if [[ "$INPUT" == "bump" ]]; then
  # bump patch
  MAJ="$(echo "$CUR_VERSION" | awk -F. '{print $1}')"
  MIN="$(echo "$CUR_VERSION" | awk -F. '{print $2}')"
  PAT="$(echo "$CUR_VERSION" | awk -F. '{print $3}')"
  [[ -z "$MIN" ]] && MIN=0
  [[ -z "$PAT" ]] && PAT=0
  NEW_VERSION="${MAJ}.${MIN}.$((PAT+1))"
  echo "Bumping version: $CUR_VERSION → $NEW_VERSION"

  # 1) Update CirriusImpact.pm
  perl -pi -e "s/(our\\s+\\\$VERSION\\s*=\\s*\")[^\"]+(\")/\\1$NEW_VERSION\\2/" "$PLUG_PERL"
  EDITED_FILE=1

  # 2) Prepend CHANGELOG entry (if file exists)
  if [[ -f "$CHANGELOG" ]]; then
    if ! grep -qE "^##[[:space:]]+$NEW_VERSION\\b" "$CHANGELOG"; then
      tmp="$(mktemp)"
      {
        echo "## $NEW_VERSION - $DATE"
        echo "- Describe the changes for $NEW_VERSION here."
        echo
        cat "$CHANGELOG"
      } > "$tmp"
      mv "$tmp" "$CHANGELOG"
      echo "CHANGELOG.md updated."
    else
      echo "CHANGELOG.md already has section for $NEW_VERSION; leaving as-is."
    fi
  fi

  # 3) Update README first obvious version mention (if file exists)
  #    - Replace 'Version: X.Y.Z' or 'version X.Y.Z' (first match only)
  #    - Or the first 'vX.Y.Z' occurrence
  if [[ -f "$README" ]]; then
    perl -0777 -pe '
      my $ver = $ENV{NEWVER};
      my $done = 0;
      # Replace "Version: X.Y.Z" or "version X.Y.Z" (first match)
      if (s/\b(V|v)ersion:\s*\K\d+\.\d+\.\d+/$ver/ && ++$done) {
      }
      # Else replace first "vX.Y.Z"
      elsif (s/\bv\d+\.\d+\.\d+\b/"v$ver"/e && ++$done) {
      }
      $_;
    ' -- - "$README" > "$README.tmp" && mv "$README.tmp" "$README"
    echo "README.md updated (first version mention → $NEW_VERSION)."
  fi

else
  NEW_VERSION="${INPUT:-$CUR_VERSION}"
  echo "Packaging using version: $NEW_VERSION (no file edits)"
fi

OUT="CirriusImpact-${NEW_VERSION}.kpz"

# ---- optional git commit & tag ----
is_git_repo() { git rev-parse --is-inside-work-tree >/dev/null 2>&1; }
GIT_PUSH="${GIT_PUSH:-0}"

if (( DO_TAG )); then
  if ! is_git_repo; then
    echo "WARN: not a git repo — skipping commit/tag" >&2
  else
    if (( EDITED_FILE )); then
      # Add edited files to commit
      git add "$PLUG_PERL" 2>/dev/null || true
      [[ -f "$CHANGELOG" ]] && git add "$CHANGELOG"
      [[ -f "$README"    ]] && git add "$README"
      if ! git diff --cached --quiet; then
        git commit -m "Bump CirriusImpact to v${NEW_VERSION}"
        echo "Committed bump to v${NEW_VERSION}."
      else
        echo "Nothing to commit for bump."
      fi
    fi

    # Create annotated tag if not existing
    if git rev-parse "v${NEW_VERSION}" >/dev/null 2>&1; then
      echo "Tag v${NEW_VERSION} already exists; leaving as-is."
    else
      git tag -a "v${NEW_VERSION}" -m "CirriusImpact v${NEW_VERSION}"
      echo "Created tag v${NEW_VERSION}"
    fi

    if [[ "$GIT_PUSH" == "1" ]]; then
      git push || true
      git push --tags || true
      echo "Pushed tag v${NEW_VERSION} (and commits)."
    else
      echo "Note: Set GIT_PUSH=1 to push the tag/commit."
    fi
  fi
fi

# ---- avoid macOS resource forks/meta ----
export COPYFILE_DISABLE=1

# ---- build KPZ (stored, no extra attrs) ----
rm -f "$OUT"
zip -r -0 -X -q "$OUT" Koha  -x '**/.DS_Store' '**/__MACOSX*' '**/.git*' '**/.idea*' '**/.vscode*' '**/*.swp'

# ---- verify & print summary ----
unzip -t "$OUT" >/dev/null
echo "Contents of $OUT:"
unzip -l "$OUT" | sed '1,3d;$d'
if command -v shasum >/dev/null 2>&1; then
  echo "SHA256: $(shasum -a 256 "$OUT" | awk '{print $1}')"
elif command -v sha256sum >/dev/null 2>&1; then
  echo "SHA256: $(sha256sum "$OUT" | awk "{print \$1}")"
fi
echo "Done: $OUT"
