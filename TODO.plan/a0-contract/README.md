# A0 — Contract and spike (#494)

## What it delivers
A written interface for amath — what goes in, what comes out, what amath may
not depend on — and a small PARG grammar that proves the four hard parts of
today's parser can be expressed that way.

## Why here
Today's parser is not a plain grammar. If PARG cannot express it without amath
reaching back into Plurimath, the port in A2 is the wrong plan. A spike on four
constructs costs a day; finding out in the middle of A2 costs the port.

## Risks and notes
- The four hard parts, on `main` at `ae20be11`:
  1. `asciimath/parse.rb:194–198` — `read_text` uses `dynamic` to read up to the
     bracket that matches the one captured earlier.
  2. `parse.rb:219–220` — the decimal marker comes from `Plurimath.configuration`.
  3. `constants.rb:88–108` — the word list is generated from Plurimath's symbol
     classes; `base_number_prefix.rb:15–24` adds more rules.
  4. `parse.rb:177` — `str("")` as a non-final alternative. Codex reports that
     Parsanol's PARG compiler rejects bare empty literals
     (`parg/compiler.rb:589–595`); not yet re-checked first-hand.
- Parsanol's `Slice` is not a `Parslet::Slice` (Codex probe, Parsanol 1.3.11).
  Parslet slices are checked well beyond the transform: `transform.rb` at 82,
  749, 786, 798, 810 and 1021, plus `math/number.rb:10`,
  `math/function/unary_function.rb:10`, `utility.rb:213`, and
  `asciimath/utility.rb:22`, which matches on the exact class.
- Parsanol has a native (Rust) and a pure-Ruby engine. Both must give the same
  trees. Parsanol silently falls back to Ruby when native is unavailable
  (`parg/artifact.rb:85–110` at `9a2c00e`, per Codex), so a match proves
  nothing unless the engine actually used is recorded.
- amath's minimum Ruby comes from the pinned Parsanol release (Codex reports
  `>= 3.2`), not from `omml`'s `>= 3.0`.

## Exit criteria
- [ ] [01 — amath contract](01-amath-contract.md) written and agreed.
- [ ] [02 — feasibility spike](02-feasibility-spike.md) passes. A failed spike
      means A0 is **blocked**, not done: A2 starts only after a successful
      spike, or after Ronald approves a revised approach and that passes its
      own spike.
- [ ] Open decisions 2 and 3 settled.
