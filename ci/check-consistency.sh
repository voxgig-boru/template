#!/usr/bin/env bash
# Packaging guard (no boru needed):
#   1. the bundled plugin SKILL.md is byte-identical to the canonical one
#      (plugins can't point at an external .claude/skills dir, so two copies
#      exist and can drift);
#   2. the JSON manifests parse;
#   3. no script invokes a retired boru flag. boru main has one execution
#      path (compile to bytecode, run on the VM); `--compile`,
#      `--force-compile` and `--no-compile` are usage errors now.
#
# The library tracks boru main (ci/boru-ref), so there is no pinned commit
# to keep in lockstep across files any more.
#
# Run directly:  ./ci/check-consistency.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
cd "$REPO"
fail=0

# 1. SKILL.md copies in sync ------------------------------------------------
canonical=.claude/skills/template-aql/SKILL.md
bundled=plugins/template-aql/skills/template-aql/SKILL.md
if diff -u "$canonical" "$bundled" >/dev/null; then
  echo "ok: SKILL.md copies identical"
else
  echo "::error file=$bundled::Plugin skill has drifted from $canonical (fix: cp $canonical $bundled)"
  fail=1
fi

# 2. JSON manifests valid ---------------------------------------------------
for j in .claude-plugin/marketplace.json \
         plugins/template-aql/.claude-plugin/plugin.json \
         api.json; do
  if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$j" >/dev/null 2>&1; then
    echo "ok: $j"
  else
    echo "::error file=$j::invalid JSON"
    fail=1
  fi
done

# 3. No retired boru flags in the scripts CI and the hook run ---------------
retired="$(grep -nE -- '--(force-|no-)?compile\b|BORU_(FORCE_|NO_)?COMPILE' \
             ci/*.sh test/divergence/run.sh .claude/hooks/*.sh 2>/dev/null \
           | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)"
if [ -z "$retired" ]; then
  echo "ok: no retired boru flags in scripts"
else
  printf '%s\n' "$retired" | sed 's/^/::error::retired boru flag: /'
  fail=1
fi

[ "$fail" = 0 ] && echo "[ci] consistency OK" || echo "[ci] consistency FAILED"
exit $fail
