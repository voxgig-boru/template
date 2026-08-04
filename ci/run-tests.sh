#!/usr/bin/env bash
# Build aql (via ci/build-aql.sh) and run every test suite. Each
# assertion-bearing suite ends by asserting Test.fail-count == 0 and prints
# `all green`; the smoke suite passes by running without error. Any failing
# suite makes this script exit non-zero. Ends with an advisory `boru check`
# (non-gating — see dx-report.md §11).
#
# Run directly:  ./ci/run-tests.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
AQL="$("$HERE/build-aql.sh")" || exit 1
echo "[ci] aql: $("$AQL" -version 2>/dev/null)"
cd "$REPO"

fail=0
for f in test/*.aql; do
  printf '[ci] %-32s ' "$f"
  if "$AQL" "$f" >/tmp/ci-suite-out 2>&1; then
    echo ok
  else
    echo FAIL
    sed 's/^/      /' /tmp/ci-suite-out
    fail=1
  fi
done

# Advisory static check of the module — NOT a gate. Checking template.aql
# alone surfaces false positives (runtime-registered parsers are invisible to
# the static pass; dynamic dispatch / mutual recursion defeat its flow
# analysis — dx-report.md §11). The gating three-surface check is
# test/divergence/run.sh, which checks the suites (clean) and asserts
# compile==interpret.
echo "[ci] advisory: boru check --soft template.aql (non-gating)"
"$AQL" check --soft template.aql 2>&1 | tail -1 || true

[ "$fail" = 0 ] && echo "[ci] PASS — all suites green." || echo "[ci] FAIL — a suite did not pass."
exit $fail
