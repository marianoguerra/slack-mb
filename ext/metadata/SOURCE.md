# Method-surface metadata

Written by `ext/scripts/vendor-fixtures.sh`. Do not edit by hand — except
`documented_methods.txt`, which is a doc scrape and is *meant* to be refreshed
(see below).

| File | What it is | Upstream |
| --- | --- | --- |
| `rate_limit_tiers.json` | 326 `"method.name": "TierN"` entries. The input to `ext/tools/gen_methods`, which turns it into `slack/methods/generated_methods.mbt`. | `java-slack-sdk/metadata/web-api/rate_limit_tiers.json` |
| `documented_methods.txt` | 309 method names scraped from Slack's reference index. | the `String methods = "..."` literal in `java-slack-sdk`'s `MethodsTest.java` |
| `excluded_methods.txt` | 30 names the Java SDK deliberately does not implement: Salesforce channel APIs, the automation-platform `apps.datastore.*` / `functions.distributions.*` / `workflows.triggers.permissions.*` families, the session-token-only `admin.audit.anomaly.allow.*`, and `assistant.search.context`. | the `excludedMethodNames` list in the same file |

`ext/test/coverage` asserts that every name in `documented ∖ excluded` (279 of
them) has both a constant and a rate-limit tier. The tier table carries 47 more
names than the doc scrape — the legacy `channels.*` / `groups.*` / `im.*` /
`mpim.*` families and a few others Slack no longer lists — and those get
constants too. Extra coverage is not an error; missing coverage is.

## Refreshing the doc scrape

Upstream's list is dated "February 26, 2026" in a comment and will drift. It
came from running this in the browser console on
<https://docs.slack.dev/reference/methods>:

```js
[].slice.call(document.getElementsByClassName('apiReferenceFilterableList__listItemLink'))
  .map(e => e.href.replace("https://docs.slack.dev/reference/methods/", ""))
```

Paste the result into `documented_methods.txt`, one per line. The coverage test
will then tell you which new methods have no tier — and a method with no tier
needs `rate_limit_tiers.json` refreshed too, which means re-running
`vendor-fixtures.sh` against a newer `java-slack-sdk`.

Note the coverage test reports *that* the two disagree, not which one is right.
