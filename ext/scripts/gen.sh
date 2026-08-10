#!/usr/bin/env bash
#
# Regenerate slack/methods/generated_methods.mbt from
# ext/metadata/rate_limit_tiers.json.
#
#   ext/scripts/gen.sh          rewrite the file and reformat
#   ext/scripts/gen.sh --check  fail if the checked-in file has drifted
#
# The --check form is a CI gate. It catches two things no normal test can: a
# hand edit to the generated file, and a metadata refresh that nobody
# regenerated against.
#
# Both forms go through `moon fmt`, so the comparison is between formatted
# files and a change to moon's formatting conventions is not reported as
# generator drift.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TARGET="$ROOT/slack/methods/generated_methods.mbt"

cd "$ROOT"

regenerate() {
  moon run --target native ext/tools/gen_methods > "$TARGET"
  moon fmt >/dev/null
}

if [ "${1-}" = "--check" ]; then
  backup=$(mktemp)
  trap 'mv -f "$backup" "$TARGET"' EXIT
  cp "$TARGET" "$backup"
  regenerate
  if diff -u "$backup" "$TARGET"; then
    echo "generated_methods.mbt is current"
  else
    echo >&2
    echo "generated_methods.mbt is stale. Run: just gen" >&2
    exit 1
  fi
else
  regenerate
  echo "wrote $TARGET"
fi
