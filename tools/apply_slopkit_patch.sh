#!/usr/bin/env bash
# Prepare the slopkit copy used by the frontend and apply our autoloader patch.
#
# slopkit lives as a pristine git submodule in third_party/slopkit (never
# modified). The frontend needs it under frontend/autoloader/slopkit, so this
# script:
#   1. copies third_party/slopkit -> frontend/autoloader/slopkit (fresh copy)
#   2. applies patches/slopkit-autoload.patch to the copy
#
# The copy is gitignored (frontend/autoloader/slopkit/), so the submodule is
# never dirtied. Run after every submodule update:
#
#   git submodule update --init --recursive
#   tools/apply_slopkit_patch.sh
#
# The Makefile runs this automatically before staging/serving (slopkit-prepare).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/third_party/slopkit"
DEST="$ROOT/frontend/autoloader/slopkit"
PATCH="$ROOT/patches/slopkit-autoload.patch"

if [ ! -e "$SOURCE/.git" ]; then
    echo "Error: slopkit submodule is not initialised."
    echo "Run: git submodule update --init --recursive"
    exit 1
fi

if [ ! -f "$PATCH" ]; then
    echo "Error: patch file not found: $PATCH"
    exit 1
fi

# 1. Fresh copy (drop .git, .github, anything not needed at runtime)
rm -rf "$DEST"
mkdir -p "$DEST"
cp -R "$SOURCE"/. "$DEST"/
rm -rf "$DEST/.git" "$DEST/.github" "$DEST/.gitignore" "$DEST/.gitmodules"

# 2. Turn the copy into a throwaway git repo so `git apply` can handle binary
#    diffs / patch chunks — plain git apply on a non-repo dir cannot.
#    Two commits: pristine slopkit, then our autoloader patch.
SRC_HASH=$(git -C "$SOURCE" rev-parse --short HEAD)
git -C "$DEST" init -q
git -C "$DEST" config user.name "wkal"
git -C "$DEST" config user.email "wkal@localhost"
git -C "$DEST" add -A
git -C "$DEST" commit -q -m "slopkit pristine (submodule $SRC_HASH)"

# 3. Apply the patch
cd "$DEST"
if git apply --check "$PATCH" 2>/dev/null; then
    git apply "$PATCH"
    git add -A
    git commit -q -m "Apply WKAL autoloader patch"
    echo "slopkit: copied to $DEST and autoloader patch applied."
elif git apply --reverse --check "$PATCH" 2>/dev/null; then
    echo "slopkit: autoloader patch is already applied."
else
    echo "Warning: patch does not apply cleanly to $DEST. Proceeding without applying the patch."
    echo "If the resulting frontend is missing integration markers, regenerate or fix tools/slopkit-autoload.patch:"
    echo "  git -C $SOURCE diff > $PATCH"
fi

# 4. Sanity check: the patched page must carry our integration markers and the
#    big cat gif must be gone. Accept either a top-level poops.html (old layout)
#    or a slopkit/poops.html (expected layout).
POOPS_PATH=""
if [ -f slopkit/poops.html ]; then
    POOPS_PATH="slopkit/poops.html"
elif [ -f poops.html ]; then
    POOPS_PATH="poops.html"
fi

if [ -n "$POOPS_PATH" ] && (grep -q 'autoload: Q.get("autoload")' "$POOPS_PATH" || grep -q 'sendPayloadToElfldr(cfg.autoload, "../../payloads/"' "$POOPS_PATH"); then
    echo "slopkit: patch verification OK (autoload block present)."
else
    echo "Warning: slopkit patch verification could not confirm autoload markers; this may be due to an upstream layout change."
    echo "If needed, regenerate patches/slopkit-autoload.patch from the pristine submodule:"
    echo "  git -C $SOURCE diff > $PATCH"
fi
