# 02 — Replay the shared outputs

Status: **pending**. Effort: **6–10 hours**. Depends on clean pinned oracle and
testsuite checkouts; does not require the port.

## Scope and proposed files

Create Plurimath `scripts/replay_asciimath_corpus.rb` and
`spec/plurimath/asciimath_corpus_replay_spec.rb`. Preserve this runner after plan
removal and document its CLI in the durable extraction handoff.

Read testsuite `corpus/provenance.yaml` at
`e9e2403b2714219fa8ed80ad863460a9c5c7db0e`. Verify generator/source revision,
Plurimath version/commit and all 27 payloads' recorded SHA-256/byte counts before
using expected results. Record the pin rather than fetching mutable main.

Implement schema-aware dispatch, not six-output assumptions. The pinned corpus
includes 13 parse-rejection records, 66 number-formatter calls, four partial
renders expecting renderer errors, and two MathML-only UnitsML records with
special arguments. Validate those inventory observations while implementing;
report counts by schema and outcome. Replay each declared target and recorded
call/arguments; assert expected errors. Fail on unknown schema, missing expected
result or zero selection. Do not silently skip unsupported records.

## Planned commands and expected outcomes

In the clean pinned Plurimath checkout after adding the proposed runner:

```sh
bundle exec ruby scripts/replay_asciimath_corpus.rb --testsuite-checkout "$PLURIMATH_TESTSUITE"
bundle exec rspec spec/plurimath/asciimath_corpus_replay_spec.rb
```

Implement the proposed option as shown; variable points to the pinned testsuite
checkout. Assert mismatched output/error, unknown schema and zero-case selection
fail nonzero; valid baseline replay passes. Save actual counts/exit codes. The
same runner and pin are A3's output gate. A2's typed/rejection gate covers all
A1 oracle cases, including those absent from the shared testsuite.

## Done when

- [ ] Provenance and payload integrity are checked before replay.
- [ ] Runner passes on original `ae20be11`; expected-error controls are meaningful.
- [ ] Actual revisions/counts/commands are recorded; no baseline failures hidden.
- [ ] A3 invokes the runner unchanged against the selected amath dependency.
