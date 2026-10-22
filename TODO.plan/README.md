# Plan

Moving Plurimath's AsciiMath parser into this repository: a PARG grammar,
compiled into a checksummed artifact, and the `amath` gem that Plurimath then
uses the way it uses `mml` and `omml`
([plurimath/plurimath#494](https://github.com/plurimath/plurimath/issues/494)).

It runs in parallel with
[plurimath/plurimath#493](https://github.com/plurimath/plurimath/issues/493),
measurement uncertainty as the GUM (JCGM 100) describes it. That work lives in
Plurimath, and its plan is in
[`TODO.uncertainty/`](https://github.com/plurimath/plurimath/tree/feat/gum-uncertainty/TODO.uncertainty)
on its branch. The two meet in two places — the AsciiMath parser and the symbol
vocabulary — so the rules for both lanes live here, in
[cross-cutting](cross-cutting.md) and [open decisions](open-decisions.md).

## Phases

Lane A is #494 (this repository and Plurimath). Lane B is #493 (Plurimath
only); its phases are listed here so the waits between lanes are visible in one
place.

| Phase | Delivers | Waits for | Status |
|---|---|---|---|
| [A0 — Contract and spike](a0-contract/) | amath's interface, and proof that PARG can express the hard parts | — | ▶ next |
| [A1 — Parity baseline](a1-baseline/) | The frozen oracle: today's trees and outputs for every input | — | ▶ next |
| [A2 — Grammar port](a2-port/) | `grammars/asciimath.parg`, artifact, corpus, gem | A0 **passed**, A1 | planned |
| [A3 — Switch Plurimath](a3-switch/) | Plurimath parses through amath; its `parse.rb` gone | A2 | planned |
| [A4 — Release](a4-release/) | amath released; Plurimath PR merged → **#494 done** | A3 | planned |
| B0–B3 — Uncertainty design, model, output, input | see [`TODO.uncertainty/`](https://github.com/plurimath/plurimath/tree/feat/gum-uncertainty/TODO.uncertainty) | — | ▶ B0 next |
| B4 — AsciiMath input for uncertainty | added to this grammar, new amath release | **A4** | blocked on lane A |

## How this is organised

Every phase is a directory whose `README.md` answers four questions in order:
*what it delivers*, *why here*, *risks and notes*, *exit criteria*.

A phase gains numbered work items when work on it starts, one file each, with a
`## Why`, a `## Scope` and a `## Done when` checklist. Only A0 and A1 have items
so far. Writing detailed scope for phases that depend on answers we don't have
yet would be guessing.

## Why this order

1. **A0 before A2** because the current grammar is not static: one rule reads
   state captured earlier in the parse, the decimal marker comes from
   configuration, and the symbol vocabulary is generated from Plurimath's own
   classes. If PARG cannot express those without amath depending on Plurimath,
   the whole approach changes, so that is proven on a small grammar first.
2. **A1 alongside A0** because the oracle must be frozen from the code as it is
   today, before anything moves. It needs nothing from A0.
3. **Plurimath's transform stays in Plurimath.** amath produces the tree;
   Plurimath keeps turning trees into its `Math::*` objects, as it does for
   MathML and OMML. That keeps amath free of Plurimath and the move small.
4. **B4 after A4** because AsciiMath input for uncertainty belongs in this
   grammar. Adding it to Plurimath's old parser first would be written twice.

## Scope boundaries

- **Opal is out of scope.** plurimath-js is to be replaced by plurimath-ts, so
  amath is not made to run under Opal. A3 removes Plurimath's plurimath-js CI
  job and says why in the PR.
