// No `import` block, and that is the point: this module depends on nothing but
// moonbitlang/core, so it checks on wasm, wasm-gc, js and native. Anything that
// needs a socket, a filesystem or an async runtime lives in the sibling `ext`
// module -- see ../moon.work.

name = "marianoguerra/slack"

version = "0.4.0"

readme = "README.mbt.md"

repository = "https://github.com/marianoguerra/slack-mb"

license = "Apache-2.0"

keywords = [ "slack", "web-api", "block-kit", "client", "bot", "chat" ]

preferred_target = "wasm"

description = "Slack Web API client: typed requests for the core method families, a generic call for the rest, Block Kit, cursor pagination, rate-limit tiers and request-signature verification. No dependencies; runs on every backend."
