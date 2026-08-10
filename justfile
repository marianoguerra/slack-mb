# Task runner for marianoguerra/slack.
#
# `moon test` covers the whole workspace from any directory, but `moon check`
# does NOT recurse into every workspace member -- so each module is checked in
# its own directory. Checking only from the root would silently skip most of it.

default: check test

# Everything CI runs, in the order CI runs it.
ci: fmt-check gen-check check backends test info-check

check:
    cd slack && moon check --deny-warn
    cd ext && moon check --deny-warn --target native

# The library must build on every backend. `ext` is native-only by design.
backends:
    cd slack && moon check --target wasm
    cd slack && moon check --target wasm-gc
    cd slack && moon check --target js
    cd slack && moon check --target native

# wasm run skips the native-only packages (transport_http, corpus_large, the
# async client tests); the native run picks them up.
test:
    moon test
    moon test --target native

fmt:
    moon fmt
    moon info

# Both of these compare the working tree against HEAD, so they can only be
# meaningful on a clean tree -- otherwise they report your own uncommitted work
# as drift. Saying so beats a mystifying `git diff --exit-code` failure.
fmt-check:
    @git diff --quiet || { echo "fmt-check needs a clean tree: it compares against HEAD"; exit 1; }
    moon fmt
    git diff --exit-code

# A stale .mbti is an unreviewed public-API change.
info-check:
    @git diff --quiet || { echo "info-check needs a clean tree: it compares against HEAD"; exit 1; }
    moon info --target all
    git diff --exit-code

# Regenerate slack/methods/generated_methods.mbt from ext/metadata/.
gen:
    ext/scripts/gen.sh

gen-check:
    ext/scripts/gen.sh --check

# Re-vendor the reference corpus from local clones of the upstream SDKs.
vendor java_sdk morphism:
    ext/scripts/vendor-fixtures.sh {{java_sdk}} {{morphism}}

# Pull the 17 fixtures too large to commit.
fixtures:
    ext/scripts/fetch-large-fixtures.sh

clean:
    moon clean
