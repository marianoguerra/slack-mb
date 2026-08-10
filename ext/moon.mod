// Not published. This module exists to keep `marianoguerra/slack` free of the
// two dependencies below: `moonbitlang/async` (the HTTP transport, native only)
// and `moonbitlang/x` (filesystem access, needed by the code generator and by
// the conformance tests that read the vendored reference fixtures).
//
// Nothing here is part of the library's public API. A consumer who wants the
// native transport copies transport_http/ or writes their own `@api.Transport`.

name = "marianoguerra/slack-ext"

version = "0.1.0"

license = "Apache-2.0"

preferred_target = "native"

description = "Native HTTP transport, method-table generator and reference-fixture conformance tests for marianoguerra/slack. Not published."

import {
  "marianoguerra/slack@0.1.0",
  "moonbitlang/async@0.20.4",
  "moonbitlang/x@0.4.49",
}
