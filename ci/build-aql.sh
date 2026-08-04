#!/usr/bin/env bash
# Ensure an `boru` interpreter built at the pinned ref (ci/aql-ref) is
# available, and echo its path on stdout. Idempotent and cacheable: if a
# usable binary already exists it is reused; otherwise aql is built from a
# codeload source tarball (works where raw `git clone` of boru-lang/boru is
# egress-blocked) and cached at ~/.local/bin/boru.
#
# Sourced/called by the other ci/ scripts and the workflow; safe to run
# directly:  ./ci/build-aql.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Track boru-lang/boru MAIN: resolve its current HEAD (env override lets CI resolve
# it once and pass it in). No pinned commit.
BORU_REF="${BORU_REF:-$(git ls-remote https://github.com/boru-lang/boru.git main | cut -f1)}"
BIN="$HOME/.local/bin/boru"

at_main() { [ -n "$BORU_REF" ] && [ "$("$1" -version 2>/dev/null | awk '{print $NF}')" = "$BORU_REF" ]; }

if [ -z "$BORU_REF" ]; then
  # Offline: reuse whatever aql is present, else fail.
  command -v aql >/dev/null 2>&1 && { command -v aql; exit 0; }
  [ -x "$BIN" ] && { echo "$BIN"; exit 0; }
  echo "error: could not resolve aql main HEAD (network?) and no aql present." >&2; exit 1
fi

# Already built at main HEAD? Reuse it.
if command -v aql >/dev/null 2>&1 && at_main aql; then
  command -v aql
  exit 0
fi
if [ -x "$BIN" ] && at_main "$BIN"; then
  echo "$BIN"
  exit 0
fi

command -v go >/dev/null 2>&1 || { echo "error: Go toolchain not found; cannot build aql." >&2; exit 1; }
echo "[ci] building aql @ $BORU_REF (one-time; cached) …" >&2
src="$(mktemp -d)"
curl -fsSL "https://codeload.github.com/boru-lang/boru/tar.gz/$BORU_REF" \
  | tar -xz -C "$src" --strip-components=1 \
  || { echo "error: could not fetch aql source." >&2; exit 1; }
mkdir -p "$(dirname "$BIN")"
( cd "$src/cmd/go" && GOWORK=off GOFLAGS=-mod=mod go build \
    -ldflags "-X github.com/boru-lang/boru/cmd/go.Version=$BORU_REF" \
    -o "$BIN" ./boru ) \
  || { echo "error: aql build failed." >&2; exit 1; }
rm -rf "$src"
echo "$BIN"
