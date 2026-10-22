# 02 — Prove PARG feasibility

Status: **pending**. Effort: **8–13 hours**. Depends on the draft comparison
contract in item 01. A failing probe blocks A2; do not expand the full port first.

## Proposed disposable work

Create untracked `tmp/amath-spike/asciimath.parg`, `cases.json` and `check.rb`
in the amath working copy. Keep the spike out of the gem and release diff;
move useful cases into A1/A2's maintained corpus and specs.

Cover these actual Plurimath constructs at the pinned oracle:

- `Parse#read_text`: captured opening bracket and matching closing delimiter;
  each delimiter pair, unmatched/Unicode delimiters, empty quoted text.
- Decimal marker in `number` and the comma-separated numeric lookahead: default
  locale and one explicit non-default decimal context, valid and rejected cases.
- `Constants.precompile_constants`, `Parse#dynamic_parser_rules` and generated
  `BaseNumberPrefix` alternatives: category labels and longest-match/tie order.
- `expression`'s non-final empty alternative: empty input, nested groups and
  valid prefixes with invalid suffixes; preserve full consumption and tree shape.

Use representative existing specs, raw versus preprocessed delimiter inputs,
non-ASCII symbols before a failure, and one input over 2,048 characters. Compare
successes against Parslet normalized typed leaves/positions and failures against
item 01's agreed rejection coordinates, separately for each engine.

## Compile, reload and observe

Select/pin a Parsanol release with PARG support; record `bundle exec ruby -v`
and `bundle exec parsanol --version` if supported by that release (otherwise
record `Parsanol::VERSION` after require). The inspected CLI supports:

```sh
bundle exec parsanol parg compile tmp/amath-spike/asciimath.parg -o tmp/amath-spike/asciimath.json
bundle exec ruby tmp/amath-spike/check.rb
```

Both commands are **planned**; grammar/driver and amath bundler setup do not yet
exist. Implement `check.rb` to load with `Parsanol::PARG::Artifact.load` from
disk, then explicitly exercise `Artifact#parse(..., mode: :native)` and
`mode: :ruby`, observing actual engine execution. Assert native availability
and no fallback on the native-required job. Run a separate controlled job with
native unavailable to establish the selected automatic/strict-native policy.
No native extension means that the native differential gate remains unfulfilled.

Corrupt copies of the artifact in the disposable directory: missing file,
malformed JSON, checksum mismatch and unsupported shape. Assert loud errors
under both engines and automatic selection; distinguish load/compatibility
errors from parse rejection. Document any selected runtime-version mismatch
probe with its actual unsupported version.

## Done when

- [ ] All four constructs compile, serialize, reload and retain oracle parity.
- [ ] Both actual engines pass; each result records engine, input/context,
      expected/actual success/tree or rejection offset, and exit code.
- [ ] Engine-unavailable and invalid-artifact cases meet the selected policy.
- [ ] Results, dependency pin, commands and limitations are summarized in the
      durable contract; unresolved limitations block the affected port work.
