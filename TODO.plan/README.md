# AsciiMath extraction execution plan

Extract Plurimath's AsciiMath parser into the standalone `amath` gem with a
PARG grammar and checksummed artifact, as required by
[Plurimath #494](https://github.com/plurimath/plurimath/issues/494).
Today `Asciimath::Parse` is a Parslet parser with runtime configuration and
generated rules. The end state is `Amath.parse` producing a compatible tree;
Plurimath retains its transform and public conversion behavior.

This is a plan, not an implementation report. All work and acceptance checks
below are pending. No compilation, parity, suite, engine or packaged-gem result
is claimed. Source references and repository bases are in
[cross-cutting](cross-cutting.md); decisions awaiting resolution are in
[open decisions](open-decisions.md).

## Phases

Lane A owns #494 in amath and Plurimath. Lane B owns
[uncertainty #493](https://github.com/plurimath/plurimath/issues/493) in Plurimath,
plus the amath grammar and release in B4, and conditional UnitsML dependency work.
[Its branch plan](https://github.com/plurimath/plurimath/tree/feat/gum-uncertainty/TODO.uncertainty)
is navigation; the shared obligations below are self-contained.

| Phase | Delivers | Prerequisite | Status |
|---|---|---|---|
| [A0](a0-contract/) | Contract, Slice/engine decisions, passing feasibility spike | none | pending |
| [A1](a1-baseline/) | Frozen typed oracle and baseline output replay | none; A0 resolves normalization before freeze | pending |
| [A2](a2-port/) | Grammar, artifact, runtime gem and conformance gate | A0 passed, A1 frozen, decisions 1–3 | pending |
| [A3](a3-switch/) | Plurimath adapter, dependency switch and agreed browser retirement | A2; Slice ownership | pending |
| [A4](a4-release/) | Packaged/published gem verified, released dependency and merged Plurimath PR | A3 | pending |
| B0–B3 | Uncertainty design, model, serializers and non-AsciiMath input | B0 contract gates each later phase | pending |
| B4 | AsciiMath uncertainty grammar, amath release and Plurimath input integration | A4 and B0–B3; B0 syntax contract | pending |

## Completion and progressive elaboration

#494 completes when the released amath dependency is used by the merged
Plurimath PR with the required suite and parity checks passing. A2 alone is
partial delivery. Preserve accepted/rejected behavior, full consumption,
configuration, typed positioned leaves, transform outputs and ordinary `+-`.
A1 freezes the Parslet oracle; neither engine may define its own expected tree.

A0 and A1 have detailed items now. A2–A4 contain executable scope, paths,
checks; expand them into numbered tasks after prerequisites pass,
using the signed contract rather than guessing unresolved APIs.

A0 and A1 may run together. B0–B3 can proceed independently with vocabulary
and Slice ownership rules observed. B4 starts after A4; do not implement its
syntax in the parser being removed. Opal implementation is excluded. A3's PR removes
the plurimath-js update/test path and states the consumer impact; Ronald's review
of that PR decides it (decision 8).

## Next handoff

Start [A0 contract](a0-contract/01-amath-contract.md) and
[A1 baseline inventory](a1-baseline/01-tree-baseline.md) on their pinned bases.
Record status, delivered revisions, actual command/exit-code evidence and next
action in each item's checklist. Keep unresolved choices pending. Before removing
this plan, preserve contracts and the B4 handoff at the durable destinations
in [cross-cutting](cross-cutting.md#durable-contracts).
