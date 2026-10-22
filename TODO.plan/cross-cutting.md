# Shared execution contracts

These rules apply to both #494 and #493. They survive independently of links to
the other lane's mutable feature branch. Proposed choices remain pending until
the named decision owner records the outcome.

## Repositories and bases

| Work | Branch | Base / ownership |
|---|---|---|
| A amath extraction | `feat/amath-extraction` in amath | amath initial base `8a153033c2b52d0aeace4f322d9f24dfbfa73c5f` |
| A Plurimath switch | `feat/amath-extraction` in Plurimath | extraction oracle `ae20be111a26fdd988c58be0bfb2b7f6fe6e352f` |
| B uncertainty | `feat/gum-uncertainty` in Plurimath | same Plurimath base; rebase onto merged A4 before B4 |
| B4 grammar and release | dedicated B4 branch in amath | released A4 tag/commit, recorded when available |
| Conditional UnitsML changes | branch in unitsml-ruby owned by B | only if B0 requires changes; record actual base/tag before assignment |

Do not apply the Plurimath SHA to amath. Record both dependency and consumer
revisions for each integration check. A1 uses an unmodified pinned oracle even
when implementation branches advance. Reconcile upstream changes before merge
and replay affected contracts; do not regenerate expected results from new code.

## File ownership in Plurimath

Paths below are repository relative. A0 records adapter versus migration and
updates this table and A3's numbered scope **before A3 starts**.

| Paths | Owner / allowed work |
|---|---|
| `lib/plurimath/asciimath/**`, `lib/plurimath/asciimath.rb` | A through A4; B4 afterward. Keep `Constants`, also used by `omml/utility.rb` and `math/function/table.rb`. |
| `lib/plurimath/asciimath/transform.rb` | No change if the boundary adapter works. Conditional A0-authorized Slice migration only during A3; B4 adds uncertainty rules after A4. |
| `lib/plurimath/math/**`, `lib/plurimath/math/function.rb` | B; exception for exact Slice consumers below only if A0 chooses migration. |
| `lib/plurimath/math/number.rb`, `lib/plurimath/math/function/unary_function.rb`, `lib/plurimath/utility.rb` | Conditional A Slice migration only; coordinate a non-overlapping change window with B. Otherwise A leaves them unchanged. |
| `lib/plurimath/unicode_math/**`, `lib/plurimath/mathml/**`, `lib/plurimath/omml/**`, `lib/plurimath/latex/**` | B. #430 also touches these; it is not built on (decision 9). |
| `plurimath.gemspec`, `Gemfile` | A adds amath; B owns agreed UnitsML bump and B4 minimum amath version; integrate sequentially. |
| Existing specs including `spec/plurimath/asciimath/**` | A freezes baseline, both preserve cases. Add new tests in separate files; coordinate edits to existing shared cases. |
| `.rspec-opal`, `Rakefile` (`spec-opal`), `.github/workflows/plurimath_js.yml`, `dependent-repos-js.json` | A removes in A3's PR; Ronald's review decides (decision 8). |
| `scripts/replay_asciimath_corpus.rb`, `spec/plurimath/asciimath_corpus_replay_spec.rb`, `spec/plurimath/asciimath_amath_spec.rb` | A (A1 replay runner and A3 checks). B does not edit them. |

The complete Slice inventory includes six checks in `asciimath/transform.rb`,
and one each in `math/number.rb`, `math/function/unary_function.rb`,
`utility.rb`, `asciimath/utility.rb` (all under `lib/plurimath/`). Prefer a
proposed `lib/plurimath/asciimath/slice_adapter.rb` constructing actual
`Parslet::Slice` leaves. If migration is required, authorize those five consumer
files explicitly and test class identity, `to_s`, `to_str`, empty strings,
`to_sym`, equality, offsets and numeric conversion behavior. String equivalence
alone does not satisfy compatibility. Preserve Parslet while this adapter or
any remaining parser needs it.

## The shared symbol vocabulary

`Constants.precompile_constants` and `Parse#dynamic_parser_rules` generate
behavior from the symbol tables, not just a set of words. A1 stores canonical
JSON containing each word, category/tree label, effective alternative order,
priority and tie-break rule; sort object keys without discarding ordered arrays.
Include `BaseNumberPrefix` generated rules and their ordering/data, or pin and
hash their exact source plus generated output. Hash these canonical bytes with
SHA-256. Record decimal/preprocessing context separately as well as compiler,
grammar source and artifact checksums; a runtime configuration fingerprint is
not the artifact checksum.

An unchanged word set with a changed category must change the fingerprint.
Identical inputs must regenerate identical bytes. Changes from A, B or upstream
require parity replay before merge. B adds no AsciiMath `INPUT` spelling before
B4. A0 chooses caller-supplied versus artifact vocabulary without making amath
depend on Plurimath; until then Plurimath is the source.

## Uncertainty contract shared with lane B

B0 must define a minimum accepted and emitted measurement form for **each** of
AsciiMath, MathML, OMML and UnicodeMath, and a model example for each supported
semantic variant. Required languages cannot be marked wholly unsupported or
output-only and still satisfy #493. For each language record syntax, recognized
form, rendered form, preserved fields, deliberate losses and executable fixture
IDs. Resolve an exception explicitly before claiming completion; optional LaTeX
input or extra notations do not replace a required capability.

B0 must distinguish standard uncertainty, symmetric expanded uncertainty and
asymmetric interval/bounds semantics. A visual `+a/−b` is not a payload. Select
named components/variants, validation, valid/unknown `k` and coverage metadata,
constructor examples, equality and round trips, with supporting JCGM sections.
Preserve supplied metadata; do not infer coverage from typography or coerce
number spellings that carry precision. Distinguish concise `1.23(4)` from
absolute `1.23(0.04)` or explicitly exclude the latter. Preserve plain `+-` as
`Math::Symbols::Pm`. B4 must use B0's agreed disambiguation and syntax.

The UnitsML attachment/model decision blocks B1. If attachment is selected, B1
owns value/unit representation and clone/equality checks, B2 serialization,
B3 non-AsciiMath parsing, B4 AsciiMath parsing plus amath release. Any dependency
change gets a B-owned unitsml-ruby base/tag, concrete task, release dependency
and measurement-with-unit preservation case in those phases. Alternatively B0
records the approved initial exclusion/deferral and supported behavior. There
is no B5. Do not silently assume a unitsml-ruby change is necessary.

## Durable contracts

Choose/confirm these proposed destinations in A0/B0, then commit them before
removing branch-only planning files:

| Repository / destination | Retained contract |
|---|---|
| amath `README.adoc` and proposed `docs/parser-contract.adoc` | Public `Amath.parse` API; preprocessing, leaf/error positions, engine/platform support, vocabulary and Slice choice |
| amath proposed `docs/extraction-handoff.adoc` | Oracle/corpus pins, vocabulary fingerprints, A4 tag, Plurimath dependency version, B0 syntax reference and B4 next actions |
| amath proposed `corpora/asciimath/` and `spec/amath/` (including B4 `spec/amath/uncertainty_spec.rb`) | Executable successful/rejected and packaged-gem contracts |
| Plurimath proposed `docs/uncertainty.adoc` | Signed semantics, required-language minimums, losses, unit choice, plain-± disambiguation and accepted syntax |
| Plurimath proposed `spec/plurimath/fixtures/uncertainty/contract.yml` and uncertainty specs | Independent GUM examples and each format's preservation/loss expectations |

After committing a contract, cite its immutable commit/tag link in the handoff;
mutable feature-branch URLs are navigation only. At A4 verify B4 can find the corpus pin and Slice/vocabulary decisions without
TODO files or feature branches. Link B0 syntax and semantic fields at their
immutable durable revision if resolved; otherwise record the B-owned unresolved
B0 blocker. This blocks B4, not extraction A4. At B's merge verify maintained docs still define GUM support.

## Checks and integration order

Existing Plurimath command: `bundle exec rake spec`. `parallel_tests` is not a
declared baseline dependency. amath currently has only `README.adoc`; its scripts,
gemspec, specs, CLI and options below are **proposed**, not runnable yet.

1. A1 validates the pinned shared corpus and runs replay on the pinned oracle.
2. A0 signs contract/ownership; A2 implements `bundle exec ruby scripts/check.rb`.
3. A3 reruns output replay and the full Plurimath suite on the actual amath ref.
4. A4 validates packaged and published gems, then B rebases onto merged A4.
5. B4 owns the uncertainty grammar/artifact, new amath release and Plurimath bump;
   replay all A parity cases and B uncertainty cases against that released gem.

Before each merge record SHA, command, actual engine, selected case count and
exit code, and required CI at that revision. Confirm effective CI versions and
platforms by reading Plurimath's delegated `generic-rake.yml` at a recorded
revision; the checked-in caller alone does not establish the matrix. Ruby >=3.2
is evidenced by Plurimath and Parsanol gemspecs, not a complete support matrix.

## Pinned public sources

- [Plurimath oracle](https://github.com/plurimath/plurimath/tree/ae20be111a26fdd988c58be0bfb2b7f6fe6e352f): parser, transform, constants, configuration, Slice consumers and `bundle exec rake spec`.
- [Testsuite](https://github.com/plurimath/plurimath-testsuite/tree/e9e2403b2714219fa8ed80ad863460a9c5c7db0e): `corpus/asciimath/` (27 payload files), `corpus/provenance.yaml`; validate checksums before replay.
- [Parsanol inspected source](https://github.com/parsanol/parsanol-ruby/tree/663a1a223b6788a21f49ca55b917e29109b6c041): `Artifact.load`, `Artifact#parse`, `Slice`, PARG compiler and gemspec. This SHA is not a selected release dependency; A0 must pin one.
- [expressir-grammar layout](https://github.com/lutaml/expressir-grammar/tree/0240350098d0ce92b8143940b7cea951bb77292b): grammar/artifact/corpus and `scripts/check.rb`. Its rejection-only check is insufficient for the error-position contract here.
- [#430](https://github.com/plurimath/plurimath/pull/430): overlapping parser migration; waits until #493/#494 merge, then rebased (decision 9).
