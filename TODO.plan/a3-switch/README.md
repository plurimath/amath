# A3 — Switch Plurimath to amath (#494)

## What it delivers
Plurimath's `Asciimath::Parser` calls amath. `asciimath/parse.rb` is deleted,
`transform.rb` stays (with only the `Slice` change, if A0 chose one), and
`amath` is a gemspec dependency.

## Why here
Only once amath passes its own gate does Plurimath have something to switch to.

## Risks and notes
- `Asciimath::Constants` stays in Plurimath; two other files use it.
- The plurimath-js CI job (`.github/workflows/plurimath_js.yml`,
  `dependent-repos-js.json`), `.rspec-opal` and the `spec-opal` Rake task are
  removed in this change, and the PR body says why (open decision 8).
- Until amath is released, Plurimath points at it by git ref for CI; the
  release in A4 replaces that.

## Exit criteria
Work items are written when A2 finishes. The gate:
- [ ] `bundle exec rake spec` passes, with the count and exit code recorded.
- [ ] A1's output replay passes.
- [ ] No file outside the A-owned list in
      [cross-cutting](../cross-cutting.md) changed.
