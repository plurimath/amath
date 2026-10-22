# 01 — Record typed trees and rejections

Status: **pending**. Inventory can start immediately;
final serialization depends on A0's agreed normalization and decisions 2–3.

## Scope and proposed paths

Create amath `scripts/bake_asciimath_baseline.rb`,
`corpora/asciimath/oracle.json` and `corpora/asciimath/manifest.json`.
The generator takes an explicit clean pinned Plurimath checkout and testsuite
checkout; it refuses a dirty/unexpected oracle revision and fails if selected
case count is zero or a schema/context cannot be reproduced. Document proposed
CLI options in its usage and durable parser contract.

Collect every input from existing `spec/plurimath/asciimath/**`,
`spec/plurimath/asciimath_spec.rb` and other specs that parse AsciiMath; locate
those uses with `rg -n -i 'asciimath|:ascii' spec`. Also collect the pinned
shared `corpus/asciimath/`. Preserve case provenance and arguments; do not
pretend static string extraction can resolve dynamic test inputs automatically.
Inventory unresolved dynamic cases explicitly and complete them before freeze.

For every case serialize raw UTF-8 input, locale/decimal/options, preprocessed
input, accepted/rejected status, and either normalized tree or rejection offset.
Preserve hash keys/ordered arrays, leaf class, text including empty text, byte
length/offset in the A0 coordinate system, with raw-input mapping if agreed.
Use separate byte/character fields where needed. Include non-ASCII failure
prefixes, default/non-default decimals at both grammar sites, raw/preprocessed
delimiters, empty input, and valid prefix plus invalid trailing input.

Record full oracle SHA, Ruby/dependency versions, schema version and the
[categorical/ordered vocabulary fingerprint](../cross-cutting.md#the-shared-symbol-vocabulary),
including base-number-prefix generated data. Source/grammar/artifact checksums
and runtime vocabulary/configuration fingerprints remain distinct.

## Planned checks

After implementing the proposed script, from amath with the two source checkouts
available at caller-selected paths:

```sh
bundle exec ruby scripts/bake_asciimath_baseline.rb --plurimath-checkout "$PLURIMATH_ORACLE" --testsuite-checkout "$PLURIMATH_TESTSUITE"
git diff --exit-code -- corpora/asciimath/oracle.json corpora/asciimath/manifest.json
```

The environment variables identify clean checkouts at the pinned public SHAs,
not user-specific paths. On first run inspect/add the generated files, then
rerun to establish byte identity. Add proposed `spec/amath/baseline_spec.rb`
controls: same words with changed category or alternative order change the
fingerprint; identical inputs do not; rejected trailing input stays rejected;
byte offsets after multibyte text are serialized unambiguously.

## Done when

- [ ] Inventory is complete; record measured total, successes and rejects.
- [ ] Repeat generation is byte-identical at the pinned oracle.
- [ ] Context, leaf types/positions and errors survive normalization.
- [ ] Category/order change invalidates fingerprint without changing the word set.
- [ ] Corpus location decision 1 is confirmed; move paths consistently if changed.
