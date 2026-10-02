#!/usr/bin/env bash
# Ensure a `boru` binary built at the tracked ref (ci/boru-ref) is available,
# and echo its path on stdout. Idempotent and cacheable: if a usable binary
# already exists it is reused; otherwise boru is built from a codeload source
# tarball (works where raw `git clone` of boru-lang/boru is egress-blocked)
# and cached at ~/.local/bin/boru.
#
# ci/boru-ref names what to track: `main` (the default — resolved to its
# current HEAD at run time) or a full 40-char commit SHA. A BORU_REF env var
# (a SHA, e.g. resolved once by the workflow) overrides it.
#
# Called by ci/run-tests.sh; safe to run directly:  ./ci/build-boru.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRACK="$(tr -d '[:space:]' < "$HERE/boru-ref" 2>/dev/null)"
TRACK="${TRACK:-main}"
if [ -z "${BORU_REF:-}" ]; then
  if printf '%s' "$TRACK" | grep -qE '^[0-9a-f]{40}$'; then
    BORU_REF="$TRACK"
  else
    BORU_REF="$(git ls-remote https://github.com/boru-lang/boru.git "$TRACK" | cut -f1 | head -1)"
  fi
fi
BIN="$HOME/.local/bin/boru"

# A ref-stamped build prints `boru <sha>` for -version.
at_ref() { [ -n "$BORU_REF" ] && [ "$("$1" -version 2>/dev/null | awk '{print $NF}')" = "$BORU_REF" ]; }

if [ -z "$BORU_REF" ]; then
  # Offline: reuse whatever boru is present, else fail.
  command -v boru >/dev/null 2>&1 && { command -v boru; exit 0; }
  [ -x "$BIN" ] && { echo "$BIN"; exit 0; }
  echo "error: could not resolve boru $TRACK (network?) and no boru present." >&2; exit 1
fi

# Already built at the ref? Reuse it.
if command -v boru >/dev/null 2>&1 && at_ref "$(command -v boru)"; then
  command -v boru
  exit 0
fi
if [ -x "$BIN" ] && at_ref "$BIN"; then
  echo "$BIN"
  exit 0
fi

command -v go >/dev/null 2>&1 || { echo "error: Go toolchain not found; cannot build boru." >&2; exit 1; }
echo "[ci] building boru @ $BORU_REF (one-time; cached) …" >&2
src="$(mktemp -d)"
curl -fsSL "https://codeload.github.com/boru-lang/boru/tar.gz/$BORU_REF" \
  | tar -xz -C "$src" --strip-components=1 \
  || { echo "error: could not fetch boru source." >&2; exit 1; }
mkdir -p "$(dirname "$BIN")"
# cmd/go → ./boru names the binary `boru`. GOWORK=off: the tarball carries
# boru's go.work, and `-mod=mod` is refused in workspace mode.
( cd "$src/cmd/go" && GOWORK=off GOFLAGS=-mod=mod go build \
    -ldflags "-X github.com/boru-lang/boru/cmd/go.Version=$BORU_REF" \
    -o "$BIN" ./boru ) \
  || { echo "error: boru build failed." >&2; exit 1; }
rm -rf "$src"
echo "$BIN"
