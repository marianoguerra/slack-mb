# Recordings

One file, and it is not vendored: `scenario.json` is a recording of
`ext/scenario`'s own run against a real Slack workspace, scrubbed and
committed, so that `ext/test/mockrun` can replay the same scenario against
`marianoguerra/slack/mock` and diff the two.

It is deliberately **not** under `ext/fixtures/`. That directory is the vendored
upstream corpus — `MANIFEST.json` and `VENDOR.md` describe where each file came
from and under which licence, and `vendor-fixtures.sh` and
`fetch-large-fixtures.sh` rewrite it wholesale. Nothing we produced belongs
there.

## Recording one

```sh
export SLACK_BOT_TOKEN=xoxb-...
export SLACK_TEST_CHANNEL='#slack-integration'   # optional; this is the default
moon run --target native ext/cmd/integration -- --record
```

`--record` with no path writes `ext/recordings/scenario.json`; pass one to write
elsewhere. `SLACK_RECORD_FILE` does the same thing for a shell that cannot pass
arguments through.

The file is scrubbed **as it is written**, not on the way out: ids become
`U00000000`/`C00000000`, timestamps become `0000000000.000000`, URLs become
`https://www.example.com/`, and time-valued numbers become `12345` — the same
placeholders java-slack-sdk uses, so a recording is comparable against
`ext/fixtures/` too. A recording of a real workspace must never carry a real
channel name or a real person's id, and the way that is guaranteed is that the
unscrubbed form is never written down.

## What the replay checks

`ext/test/mockrun` runs the same scenario against `Workspace::demo()` and
compares, in this order:

1. **the same methods, in the same order** — the cheapest check, and the one
   that localises the other two when it fails;
2. **the same shape, both ways round** — a key present on one side only fails
   whichever side it is on;
3. **equal values, on the paths the scenario itself chose** — `ok`, the error
   code, the text and blocks of the message it wrote, the arguments `api.test`
   echoed back. Not the whole payload: a real workspace and `demo()` hold
   different people in differently named channels, so byte equality is
   unachievable and chasing it would produce a golden that had to be re-recorded
   weekly.

Without a recording the test **skips, loudly**, so a fresh clone and CI are both
green. Re-record when Slack changes something, not on a schedule.
