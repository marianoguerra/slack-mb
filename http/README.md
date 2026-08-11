# marianoguerra/slack-http

The native HTTP transport for [`marianoguerra/slack`](https://mooncakes.io/docs/marianoguerra/slack),
over [`moonbitlang/async`](https://mooncakes.io/docs/moonbitlang/async).

```sh
moon add marianoguerra/slack
moon add marianoguerra/slack-http
```

```moonbit
import {
  "marianoguerra/slack/client",
  "marianoguerra/slack-http/transport",
}
```

```moonbit
let client = @client.Client::new(@transport.HttpTransport::new(), token)
let me = client.auth_test()
```

`HttpTransport::new` takes an optional `description`, used only in error
messages — a transport that cannot say where it was pointed makes a connection
failure much harder to place.

## Why this is a separate module

In MoonBit the module is the unit of publication *and* of dependencies, so an
import applies to every package in it. Putting this file in
`marianoguerra/slack` would put an async runtime in the dependency graph of
someone who only wants Block Kit on wasm-gc. So the library depends on nothing
outside `moonbitlang/core` and builds on wasm, wasm-gc, js and native; this
module is native-only and opt-in.

## You may not need it

`@api.Transport` is a two-method trait, and implementing it over whatever HTTP
client your host already has is a dozen lines:

```moonbit
pub impl @api.Transport for MyTransport with fn send(self, request) {
  // POST request.url with request.body and request.headers, then answer:
  { status: ..., headers: ..., body: ... }
}
```

Two rules the library relies on, both of which this module's source documents
where it obeys them:

- **Lowercase the response header names.** Slack's casing is not stable across
  edges, and `@api`'s envelope reader — `Retry-After` in particular — expects
  them lowercased.
- **Do not forward `content-length`.** `@api` computes it so a caller
  inspecting a request can see it, but most HTTP clients compute their own, and
  sending both risks two conflicting headers on the wire.

For tests, use `@slack/testing`'s `FakeTransport` (a scripted list of responses)
or `@slack/mock`'s `Workspace` (an in-memory Slack with state). Neither needs a
socket, and both are in the dependency-free library.

## License

Apache-2.0, the same as the library. See [LICENSE](LICENSE).
