#!/bin/sh
# Build the project's Bend toolchain from source: upstream Bend 2.0.7
# (github.com/bendlang/bend at the commit below) plus patches/series, each
# applied with `patch -p1` inside bend2/. The result must match
# patches/toolchain.sha256 file for file; nothing is installed otherwise.
#
#   scripts/install-bend-toolchain.sh [DEST]   default build/bend-native-toolchain/bend2
#   scripts/install-bend-toolchain.sh --check [DIR]   verify an existing toolchain
#
# BEND_UPSTREAM names a bendlang/bend clone (default build/bend-upstream,
# cloned when missing). Replacing a toolchain while a build runs breaks that
# build: check `pgrep -f bend2/main.ts` first.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
COMMIT=fb36663571742100b349b84d615a2fdbd37ed678
SUMS="$ROOT/patches/toolchain.sha256"
DEFAULT="$ROOT/build/bend-native-toolchain/bend2"

verify() {
  (cd "$1" && sha256sum --quiet -c "$SUMS") || { echo "toolchain $1 does not match $SUMS" >&2; return 1; }
  extra=$(cd "$1" && find . -type f ! -name '*.orig' | sed 's#^\./##' | sort | comm -23 - "$FILES")
  [ -z "$extra" ] || { echo "toolchain $1 has files outside the series: $extra" >&2; return 1; }
}

FILES=$(mktemp); awk '{print $2}' "$SUMS" | sort > "$FILES"
trap 'rm -f "$FILES"' EXIT
if [ "${1:-}" = --check ]; then
  verify "${2:-$DEFAULT}" && echo "toolchain ${2:-$DEFAULT} matches upstream $COMMIT + patches/series"
  exit
fi

DEST=${1:-$DEFAULT}
UP=${BEND_UPSTREAM:-$ROOT/build/bend-upstream}
[ -d "$UP/.git" ] || git clone -q https://github.com/bendlang/bend "$UP"
git -C "$UP" cat-file -e "$COMMIT^{commit}" 2>/dev/null || git -C "$UP" fetch -q origin
TMP=$(mktemp -d "${DEST%/*}/.bend-toolchain.XXXXXX" 2>/dev/null || { mkdir -p "${DEST%/*}"; mktemp -d "${DEST%/*}/.bend-toolchain.XXXXXX"; })
trap 'rm -rf "$TMP" "$FILES"' EXIT
git -C "$UP" archive "$COMMIT" bend2/bend.ts bend2/comp.ts bend2/base.bend bend2/main.ts bend2/effs | tar -x -C "$TMP"
while read -r p; do
  patch -p1 -s -f -d "$TMP/bend2" -i "$ROOT/patches/$p" || { echo "patches/$p does not apply" >&2; exit 1; }
done < "$ROOT/patches/series"
verify "$TMP/bend2"
[ ! -e "$DEST" ] || mv "$DEST" "$DEST.old.$$"
mv "$TMP/bend2" "$DEST"
rm -rf "$DEST.old.$$"
echo "installed upstream $COMMIT + $(wc -l < "$ROOT/patches/series") patches at $DEST"
