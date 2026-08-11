// The native HTTP transport, as its own module, because in MoonBit the module
// is the unit of publication AND of dependencies.
//
// It cannot live in `marianoguerra/slack`: an import there applies to the whole
// module, so `moonbitlang/async` would land in the dependency graph of someone
// who only wants Block Kit on wasm-gc. It should not stay in
// `marianoguerra/slack-ext` either -- that module is not published, and it
// carries the code generator, `moonbitlang/x` and 5 MB of vendored fixtures
// that no consumer of a transport has any use for.
//
// So: one module, one file, two dependencies. What a caller who wants to talk
// to Slack over a socket needs, and nothing else.

name = "marianoguerra/slack-http"

version = "0.3.0"

readme = "README.md"

repository = "https://github.com/marianoguerra/slack-mb"

license = "Apache-2.0"

keywords = [ "slack", "web-api", "http", "transport", "client" ]

preferred_target = "native"

description = "Native HTTP transport for marianoguerra/slack, over moonbitlang/async. Implements @api.Transport; native target only."

import {
  "marianoguerra/slack@0.3.0",
  "moonbitlang/async@0.20.4",
}
