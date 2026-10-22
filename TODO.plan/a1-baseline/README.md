# A1 — Parity baseline (#494)

## What it delivers
The oracle for the port: for every AsciiMath input we know of, the tree today's
parser produces and the output Plurimath renders from it, frozen at
`ae20be11`.

## Why here
"The new parser behaves the same" is only checkable against a record of how the
old one behaved, made before anything moves. It needs nothing from A0, so it
runs alongside it.

## Risks and notes
- Two levels of parity, and both are needed:
  - **trees**, so `transform.rb` can stay unchanged;
  - **outputs**, which is what users see.
- plurimath-testsuite already has 27 AsciiMath case files generated from
  `ae20be11`, with outputs and string-only parse trees. A1 reuses them, and
  adds what they lack: typed, positioned trees, and inputs from Plurimath's own
  specs that the shared corpus does not have.
- The output replay supplements Plurimath's full suite; it does not replace it.
- Inputs depend on context: the decimal marker, locale, and the preprocessing
  in `parser.rb:9–14`. Each case records the context it was made in.
- `+-` cases stay in. They are plain ± and must still be after #493.

## Exit criteria
- [ ] [01 — tree baseline](01-tree-baseline.md) recorded.
- [ ] [02 — output replay](02-output-replay.md) wired to the testsuite corpus.
- [ ] The symbol vocabulary fingerprint is recorded (see
      [cross-cutting](../cross-cutting.md#the-shared-symbol-vocabulary)).
