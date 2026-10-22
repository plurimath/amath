# Cross-cutting

What both lanes depend on, and the rules that keep them from colliding.

## Branches and worktrees

| Lane | Branch | Repos |
|---|---|---|
| A (#494) | `feat/amath-extraction` | amath, and later plurimath |
| B (#493) | `feat/gum-uncertainty` | plurimath (and unitsml-ruby if B0 says so) |

Both branch from Plurimath `main` at `ae20be11` (2026-10-20, v0.11.12).

## File ownership in Plurimath

| Area | Owner | Rule |
|---|---|---|
| `lib/plurimath/asciimath/**` | A | B does not touch it until A4 |
| `asciimath/transform.rb` | A, read-only during A | B4 adds rules only after A4 merges |
| `asciimath.rb` autoloads | A | A replaces the `Parse` autoload; **keeps `Constants`**, used by `omml/utility.rb:16` and `math/function/table.rb:43` |
| `lib/plurimath/math/**` | B | A changes nothing here |
| `math/function.rb` autoload list | B | add-only |
| `lib/plurimath/utility.rb` | nobody | neither lane edits it; B puts helpers in its own module |
| `unicode_math/**`, `mathml/**`, `omml/**`, `latex/**` | B | A changes nothing |
| `plurimath.gemspec`, `Gemfile` | A adds `amath` | B changes them only for a unitsml bump, and at B4 for the amath minimum version |
| Existing specs, incl. `asciimath_spec.rb`, `math/formula_spec.rb` | shared | neither lane rewrites existing cases; new cases go in new files |
| `spec/plurimath/asciimath/**` | A | frozen as the baseline; B adds specs elsewhere |
| `.rspec-opal`, `Rakefile` `spec-opal`, `.github/workflows/plurimath_js.yml`, `dependent-repos-js.json` | A | A removes them; B does not touch |

## The shared symbol vocabulary

This is the one place the lanes meet in the middle, and directory ownership
does not cover it.

The AsciiMath grammar's word list is not written in the grammar. It is built
at load time from every symbol class's `INPUT` table
(`asciimath/constants.rb:88–108` via `Utility.symbols_hash`). Those classes
live in `lib/plurimath/math/`, which is lane B's.

Rules:

- A1 records a **fingerprint** of the vocabulary (sorted words → SHA-256) with
  the baseline.
- B does **not** add AsciiMath spellings to any `INPUT` table before B4.
- Any change to the fingerprint, from either lane or from `main`, re-runs A's
  parity corpus before merge.
- A0 decides how amath receives the vocabulary (shipped with the artifact, or
  passed in). Until then, Plurimath remains the source.

## Sync points

1. **After A1:** the corpus keeps the existing `+-` cases. They are plain ±,
   and they must still parse as `Math::Symbols::Pm` after both lanes land.
2. **After B0 is approved:** A records the agreed AsciiMath syntax for
   uncertainty in [open decisions](open-decisions.md), so the grammar leaves
   room for it without clashing with `+-` or parentheses.
3. **After A4 merges:** rebase `feat/gum-uncertainty` onto `main`, then start B4.
4. **Before either PR is marked ready:** run the full suite on both branches,
   each rebased on the latest `main`.

## Verification commands

- Plurimath full suite: `bundle exec rake spec`. (`parallel_tests` is not a
  declared dependency on `main`, so it is not the gate.)
- amath conformance: `scripts/check.rb` (written in A2), following
  `lutaml/expressir-grammar`.
- Every recorded result names the commit, command and exit code.

## Existing work to reuse

- **plurimath-testsuite** already holds an AsciiMath corpus generated from
  Plurimath `ae20be11` (`corpus/asciimath/`, 27 files, provenance in
  `corpus/provenance.yaml`): inputs with expected AsciiMath, LaTeX, MathML,
  UnicodeMath, OMML and HTML output. A1 uses it for output replay rather than
  generating a second copy.
- **plurimath-ts** has already ported this grammar once, to its pegkit parser
  (`TODO.plan/p1-asciimath/04-asciimath-grammar.md`). Its notes on the grammar's
  quirks are input to A0 and A2.
- **lutaml/expressir-grammar** is the layout to copy: grammar source, checksummed
  artifact, frozen corpus, `scripts/check.rb` gate.
