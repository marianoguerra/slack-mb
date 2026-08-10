#!/usr/bin/env bash
#
# Fetch the reference fixtures too large to commit.
#
# ext/fixtures/MANIFEST.json lists every file the corpus tests know about,
# including the 17 at or above 512 KB that .gitignore keeps out of the repo.
# Those 17 are 38 MB -- three quarters of the whole corpus -- and only one test
# reads them, so a clone should not have to carry them.
#
# This re-fetches exactly those, from the commit MANIFEST.json was generated
# against, and verifies each against its recorded sha256. `ext/test/corpus_large`
# skips with a log line when they are absent.
set -euo pipefail

EXT=$(cd "$(dirname "$0")/.." && pwd)
MANIFEST="$EXT/fixtures/MANIFEST.json"

[ -f "$MANIFEST" ] || { echo "no $MANIFEST -- run vendor-fixtures.sh first" >&2; exit 1; }

commit=$(python3 -c '
import json,sys
m = json.load(open(sys.argv[1]))
print(next(s["commit"] for s in m["sources"] if "java-slack-sdk" in s["repo"]))
' "$MANIFEST")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "cloning java-slack-sdk at $commit (shallow, blobless)"
git clone --filter=blob:none --no-checkout --quiet \
  https://github.com/slackapi/java-slack-sdk "$tmp/java-slack-sdk"
git -C "$tmp/java-slack-sdk" fetch --quiet --depth 1 origin "$commit"
git -C "$tmp/java-slack-sdk" checkout --quiet "$commit" -- json-logs

python3 - "$MANIFEST" "$EXT/fixtures" "$tmp/java-slack-sdk" <<'PY'
import hashlib, json, pathlib, sys

manifest, dest_root, src_root = (pathlib.Path(p) for p in sys.argv[1:4])
m = json.loads(manifest.read_text())

# `java/api-large/chat.postMessage.json` came from `json-logs/samples/api/...`;
# `java/raw-large/...` from `json-logs/raw/...`.
def upstream(rel: str) -> pathlib.Path:
    _, group, *rest = rel.split("/")
    group = group.removesuffix("-large")
    base = "raw" if group == "raw" else f"samples/{group}"
    return src_root / "json-logs" / base / "/".join(rest)

ok = missing = 0
for f in m["files"]:
    if f["tier"] != "large":
        continue
    src = upstream(f["path"])
    if not src.exists():
        print(f"MISSING upstream: {src}")
        missing += 1
        continue
    data = src.read_bytes()
    got = hashlib.sha256(data).hexdigest()
    if got != f["sha256"]:
        print(f"CHECKSUM MISMATCH {f['path']}\n  expected {f['sha256']}\n  got      {got}")
        missing += 1
        continue
    dest = dest_root / f["path"]
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(data)
    ok += 1

print(f"fetched {ok} large fixtures" + (f", {missing} failed" if missing else ""))
raise SystemExit(1 if missing else 0)
PY
