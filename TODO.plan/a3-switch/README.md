# A3 — Switch Plurimath to amath

Status: **pending**. Starts after A2 acceptance and A0's final Slice ownership
update. Decisions 8 and 9 are recorded in [open decisions](../open-decisions.md). Expand
numbered items against the actual A2 API and ref, preserving these gates.

## Work

| Task | Paths / behavior | Status |
|---|---|---|
| Adapter and dependency switch | `lib/plurimath/asciimath/parser.rb` (`Parser#parse`), `lib/plurimath/asciimath.rb`, `plurimath.gemspec`, `Gemfile`; proposed `lib/plurimath/asciimath/slice_adapter.rb` | pending |
| Accepted retirement and compatibility validation | `.github/workflows/plurimath_js.yml`, `dependent-repos-js.json`, `.rspec-opal`, `Rakefile` `spec-opal`; proposed `spec/plurimath/asciimath_amath_spec.rb` and preserved A1 replay | pending |

If migration is selected, enumerate its exact edits in numbered
work items and shared ownership before starting, not after a scope-check failure.

## Implementation instructions

Replace the `Asciimath::Parse` call with the signed `Amath.parse` interface and
selected preprocessing/configuration mapping. Remove
`lib/plurimath/asciimath/parse.rb` and its autoload only after tests pass through
amath. Keep `Constants` and the Plurimath transform. If the Slice boundary
adapter succeeds, leave all five existing consumers unchanged. Otherwise the
only additional authorized consumer paths are A0's explicit list in
[cross-cutting](../cross-cutting.md#file-ownership-in-plurimath), coordinated with B.

Use a recorded amath git ref for interim CI, then released version in A4. Keep
Parslet as required by real Slice construction or remaining parsers. #430 is not
built on; it is rebased after #493 and #494 merge (decision 9).

Opal implementation is excluded. The PR removes the browser update/test files
and states the impact: plurimath-js stops following Plurimath until plurimath-ts
replaces it. Put the same note in the release notes. Ronald's review of the PR
decides it (decision 8); if he asks to keep the path, drop the removal from the
PR and keep its checks.

## Planned checks

Existing Plurimath suite command and proposed A1 runner/spec:

```sh
bundle exec rake spec
bundle exec ruby scripts/replay_asciimath_corpus.rb --testsuite-checkout "$PLURIMATH_TESTSUITE"
bundle exec rspec spec/plurimath/asciimath_amath_spec.rb
```

Assert adapter leaf class/empty text/offset/conversion compatibility, configuration
at both decimal sites, accepted/rejected/full-consumption parity, Formula-level
outputs and plain `+-`. Use A1 cases rather than recomputing expectations. Inspect
the final file diff against the finalized ownership list, and inspect required
CI on the actual dependency ref; deleted checks are not proof of Ruby support.

## Exit criteria

- [ ] Full suite and A1 replay pass with counts, SHAs and exit codes recorded.
- [ ] Public parse/conversion behavior and Slice consumer compatibility preserved.
- [ ] Dependency still satisfies remaining Parslet consumers; Constants retained.
- [ ] Browser removal, decision timing and release/PR documentation agree.
- [ ] No changes outside the signed A-owned paths; B integration conflicts resolved.

Next: hand the passing integration ref and actual support matrix to A4; no gem
publication is performed merely by completing this plan.
