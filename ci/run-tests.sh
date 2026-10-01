#!/usr/bin/env bash
# Build boru (via ci/build-boru.sh) and run every test suite, then check the
# library module. On boru main a run compiles the program to bytecode and
# runs it on the VM — the only execution path (the interpreter fallback and
# the --compile / --force-compile / --no-compile flags are retired) — after a
# static pre-flight check whose errors block the run.
#
# Each assertion-bearing suite ends by asserting Test.fail-count is 0 and
# prints `all green`; the smoke suite passes by running without error. Any
# failing suite, or a `boru check template.aql` that reports an error, makes
# this script exit non-zero. (The per-suite `boru check` gate lives in
# test/divergence/run.sh, the workflow's second job.)
#
# Run directly:  ./ci/run-tests.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
BORU="$("$HERE/build-boru.sh")" || exit 1
echo "[ci] boru: $BORU ($("$BORU" -version 2>/dev/null))"
cd "$REPO"

out_file="$(mktemp)"
trap 'rm -f "$out_file"' EXIT

fail=0
for f in test/*.aql; do
  printf '[ci] %-32s ' "$f"
  if "$BORU" "$f" >"$out_file" 2>&1 \
     && { ! grep -q 'Test.fail-count' "$f" || grep -qx 'all green' "$out_file"; }; then
    echo ok
  else
    echo FAIL
    sed 's/^/      /' "$out_file"
    fail=1
  fi
done

# The module checked standalone must report 0 errors (infos are expected:
# runtime-registered parsers are dynamic to the static pass — see
# test/divergence/README.md).
printf '[ci] %-32s ' "boru check template.aql"
if "$BORU" check template.aql >"$out_file" 2>&1; then
  echo "ok ($(grep -E '^check: [0-9]+ error' "$out_file" | tail -1 | sed 's/^check: //'))"
else
  echo FAIL
  sed 's/^/      /' "$out_file"
  fail=1
fi

[ "$fail" = 0 ] && echo "[ci] PASS — all suites green; module checks clean." || echo "[ci] FAIL — a suite or the module check did not pass."
exit $fail
