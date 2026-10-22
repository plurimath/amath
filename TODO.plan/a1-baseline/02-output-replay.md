# TODO 2 — Replay outputs from the shared testsuite

## Why
Identical trees should give identical output, but "should" is not evidence.
The testsuite already holds the expected outputs, made from the same commit we
start from, so replaying them costs little and catches anything the tree
comparison misses.

## Scope
- Use plurimath-testsuite's `corpus/asciimath/` at a pinned commit (currently
  `e9e2403`, generated from Plurimath `ae20be11` per `corpus/provenance.yaml`).
- Check the pin's provenance before trusting it: generator commit, Plurimath
  version and commit, payload checksums.
- A runner that reads each case by its schema and declared targets, not as
  "six outputs per input". At `e9e2403` the files include, per Codex: 13 parse
  rejections, 66 cases that call the number formatter, four partial-render
  cases that expect a renderer error, and two MathML-only UnitsML cases with
  their own call arguments. The runner:
  - compares each declared target's output;
  - replays recorded calls with their arguments;
  - asserts expected errors;
  - fails on an unknown schema, a missing expectation, or zero cases selected.
- Run it on `ae20be11` first; it must pass there before it can judge anything
  else.

## Done when
- [ ] The runner passes on `ae20be11`, with the case count and exit code
      recorded.
- [ ] The testsuite pin and its provenance check are written down.
- [ ] It runs as part of A3's gate.
