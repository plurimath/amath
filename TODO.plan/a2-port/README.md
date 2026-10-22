# A2 — Port the grammar and package the runtime

Status: **pending**. Starts after A0 passes, A1 freezes, and decisions 1–3 are
resolved. Expand numbered work items against those contracts at that point.

## Deliverables

| Task | Exact existing/proposed touchpoints | Status |
|---|---|---|
| Port static and generated grammar | Existing Plurimath `lib/plurimath/asciimath/parse.rb`, `lib/plurimath/asciimath/constants.rb`, `lib/plurimath/base_number_prefix.rb`; proposed amath `grammars/asciimath.parg`, `artifacts/asciimath.json` and selected generated tables | pending |
| Implement standalone gem boundary | Proposed `amath.gemspec`, `Gemfile`, `lib/amath.rb`, `lib/amath/parser.rb`; `Amath.parse`, selected error and engine interfaces from A0 | pending |
| Conformance and packaged-runtime checks | Proposed `scripts/check.rb`, `scripts/check_installed_gem.rb`, `spec/amath/parser_spec.rb`, `spec/amath/artifact_spec.rb`, `.github/workflows/test.yml` | pending |

A1 owns baseline fixture construction; A2 consumes it.

## Implementation boundary

Transcribe the 38 handwritten rules and all generated alternatives, preserving
capture labels, order, decimal lookahead and full consumption. No uncertainty
syntax is introduced here. Record source/compiler/artifact checksum and caller
configuration fingerprint distinctly. Recompilation with identical inputs must
be deterministic. Package grammar/embedded source, tables/imports required for
Ruby execution and corpus as selected by the gem contract; verify installed
runtime works without a checkout. Use the expressir-grammar layout as reference,
not its weaker reject-status-only gate.

amath depends on Parsanol only; no require of Plurimath or its constants.
Metadata proposal follows omml (Ribose Inc., open.source@ribose.com,
BSD-2-Clause); check license contents and set Ruby minimum from the selected
Parsanol release (inspected minimum is >=3.2).

## Required conformance gate

Implement the proposed command, its arguments and nonzero failure semantics:

```sh
bundle exec ruby scripts/check.rb --plurimath-checkout "$PLURIMATH_ORACLE"
bundle exec rspec spec/amath/parser_spec.rb spec/amath/artifact_spec.rb spec/amath/conformance_spec.rb
```

The supplied clean checkout is the A1 pinned Plurimath oracle used for its
unchanged transform/output comparison; use the A0 adapter contract for leaves.
Every A1 case runs under each **actual** required engine:

- Successful cases independently match the frozen Parslet normalized tree,
  exact leaf/position contract and expected transform outputs. Agreement between
  native and Ruby alone is insufficient.
- Rejected cases independently remain rejected in identical preprocessing,
  locale/decimal/options and match the A0/A1 failure-coordinate contract.
  Invalid text after a valid prefix must fail full consumption.
- Fail if either engine produces the same wrong tree, accepts a baseline reject,
  changes its agreed offset, selects zero cases, or uses the wrong engine.
- Add meaningful checker controls in proposed `spec/amath/conformance_spec.rb`:
  wrong expected leaf/offset, unexpected acceptance and invalid trailing input
  cause failure; unchanged ordinary algebra, parentheses, decimals and `+-`
  retain their frozen result. These controls verify assertions, not just exit 0.

Run installed-gem checks via proposed `scripts/check_installed_gem.rb` after
`gem build amath.gemspec`. Implement its CLI as described in A4. Native-capable
jobs must prove both engines; a deliberate no-native job proves selected
fallback/strict-native behavior. Missing/malformed/checksum-invalid/unsupported
artifacts must fail loudly in all supported modes. Record actual engines and
platforms. Inspect the effective CI matrix before adding explicit support jobs;
do not infer it from Plurimath's reusable-workflow caller.

## Exit criteria / #494 mapping

- [ ] Standalone PARG artifact and gem implement the signed A0 API.
- [ ] All successful A1 cases match oracle tree/leaves/offsets and outputs on each engine.
- [ ] All rejected A1 cases preserve rejection, agreed offset and context.
- [ ] Fingerprint and checksum controls fail appropriately; regeneration is deterministic.
- [ ] Installed-gem engine/fallback/error policy passes for documented platforms.
- [ ] Record dependency pin, artifact hash, counts, actual engines, SHA and exits.

Next handoff: A3 receives a consumable amath ref, recorded Slice decision and
passing gates. No existing Plurimath parser is deleted until this acceptance passes.
