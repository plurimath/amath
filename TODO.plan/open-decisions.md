# Open decisions

Each has an owner and the point where it blocks work. Settled decisions move to
the bottom with the date and who settled them.

## Open

| # | Decision | Owner | Blocks | Proposal |
|---|---|---|---|---|
| 1 | Does the grammar live in `plurimath/amath` with the gem, or in its own grammar repo (the `expressir-grammar` / `postscript-parg` pattern) that other implementations such as plurimath-ts could also load? | Ronald | A2 | One repo, as #494 asks; `grammars/` and `artifacts/` can move out later without changing the gem's API. |
| 2 | How amath gets the symbol vocabulary: shipped inside the artifact (amath owns it) or passed in by the caller (Plurimath owns it). | Suleman, from A0's result | A2 | Decided by A0's spike. |
| 3 | How amath gets the decimal marker and other configuration. | Suleman, from A0's result | A2 | A keyword argument to `Amath.parse`, defaulting to `.`. |
| 4 | Which uncertainty notations #493 covers: `x ± u`, concise `1.23(4)`, expanded `U` with coverage factor `k`, asymmetric `+a/−b`. | Ronald, via B0 | B1 | All four in the model; formats may support a subset. |
| 5 | How plain `±` differs from measurement uncertainty in each input format. | Ronald, via B0 | B3, B4 | B0 proposes one rule per format. |
| 6 | LaTeX: input as well, or output only? | Ronald, via B0 | B3 | Output only first; input if B0 finds a clear notation. |
| 7 | Does uncertainty link to UnitsML (`9.81 ± 0.02 m/s²`)? | Ronald, via B0 | B5 (if any) | Model it so a unit can attach; UnitsML work only if he asks. |
| 8 | Timing of dropping plurimath-js: #494 removes its CI job; if it merges before plurimath-ts replaces plurimath-js, plurimath-js stops following Plurimath. | Ronald, in PR review | A4 | State it in the PR body. |

## Settled

- **2026-10-22, Suleman:** the two issues run in parallel; AsciiMath input for
  #493 waits for #494.
- **2026-10-22, Suleman:** #494 is done when the Plurimath PR merges with the
  full suite passing.
- **2026-10-22, Suleman:** Opal is out of scope; plurimath-js is being replaced
  by plurimath-ts.
- **2026-10-22, Suleman:** no separate comment to Ronald before the PR; #494
  already names the gem and PARG.
- **2026-10-22, Suleman:** the repo is `plurimath/amath`, public, created
  empty; first commit `8a15303` "Add README".
