#!/usr/bin/env bash
#
# Regenerate the two generated files from ext/metadata/:
#
#   slack/methods/generated_methods.mbt  from rate_limit_tiers.json
#   slack/model/generated_model.mbt      from model.json
#
#   ext/scripts/gen.sh          rewrite them and reformat
#   ext/scripts/gen.sh --check  fail if either checked-in file has drifted
#
# The --check form is a CI gate. It catches two things no normal test can: a
# hand edit to a generated file, and a metadata refresh that nobody regenerated
# against.
#
# Both forms go through `moon fmt`, so the comparison is between formatted
# files and a change to moon's formatting conventions is not reported as
# generator drift.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)

cd "$ROOT"

# tool:target, one per generated file.
GENERATED=(
  "gen_methods:slack/methods/generated_methods.mbt"
  "gen_model:slack/model/generated_model.mbt"
)

regenerate() {
  for pair in "${GENERATED[@]}"; do
    moon run --target native "ext/tools/${pair%%:*}" > "${pair##*:}"
  done
  # Once, after both: `moon fmt` walks the whole workspace anyway.
  moon fmt >/dev/null
}

if [ "${1-}" = "--check" ]; then
  backups=()
  restore() {
    for i in "${!GENERATED[@]}"; do
      mv -f "${backups[$i]}" "${GENERATED[$i]##*:}"
    done
  }
  for pair in "${GENERATED[@]}"; do
    backup=$(mktemp)
    cp "${pair##*:}" "$backup"
    backups+=("$backup")
  done
  trap restore EXIT
  regenerate
  stale=0
  for i in "${!GENERATED[@]}"; do
    target="${GENERATED[$i]##*:}"
    if ! diff -u "${backups[$i]}" "$target"; then
      echo >&2
      echo "$(basename "$target") is stale. Run: just gen" >&2
      stale=1
    fi
  done
  if [ "$stale" -ne 0 ]; then
    exit 1
  fi
  echo "generated files are current"
else
  regenerate
  for pair in "${GENERATED[@]}"; do
    echo "wrote ${pair##*:}"
  done
fi
