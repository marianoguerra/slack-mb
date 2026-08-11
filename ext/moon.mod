// Not published. This module holds the things a consumer has no use for: the
// code generator, the conformance tests over 5 MB of vendored fixtures, the
// demo CLI and the integration scenario. What they drag in -- `moonbitlang/x`
// for filesystem access, `moonbitlang/async` for the tests that must be async
// -- is what keeps `marianoguerra/slack` free of both.
//
// The native transport used to live here too, which made it unpublishable for
// no better reason than its neighbours. It is `marianoguerra/slack-http` now,
// and this module is one of its consumers.

name = "marianoguerra/slack-ext"

version = "0.3.0"

license = "Apache-2.0"

preferred_target = "native"

description = "Code generators, reference-fixture conformance tests and the demo CLI for marianoguerra/slack. Not published."

import {
  "marianoguerra/slack@0.3.0",
  "marianoguerra/slack-http@0.3.0",
  "moonbitlang/async@0.20.4",
  "moonbitlang/x@0.4.49",
}
