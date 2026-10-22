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

## Phases and effort

Lane A owns #494 in amath and Plurimath. Lane B owns
[uncertainty #493](https://github.com/plurimath/plurimath/issues/493) in Plurimath,
plus the amath grammar and release in B4, and conditional UnitsML dependency work.
[Its branch plan](https://github.com/plurimath/plurimath/tree/feat/gum-uncertainty/TODO.uncertainty)
is navigation; the shared obligations below are self-contained.

| Phase | Delivers | Prerequisite | Effort (hours) | Status |
|---|---|---|---|---|
| [A0](a0-contract/) | Contract, Slice/engine decisions, passing feasibility spike | none | 12–20 | pending |
| [A1](a1-baseline/) | Frozen typed oracle and baseline output replay | none; A0 resolves normalization before freeze | 14–24 | pending |
| [A2](a2-port/) | Grammar, artifact, runtime gem and conformance gate | A0 passed, A1 frozen, decisions 1–3 | 28–48 | pending |
| [A3](a3-switch/) | Plurimath adapter, dependency switch and agreed browser retirement | A2; decisions 8–9 and Slice ownership | 12–22 | pending |
| [A4](a4-release/) | Packaged/published gem verified, released dependency and merged Plurimath PR | A3 | 8–14 | pending |
| B0–B3 | Uncertainty design, model, serializers and non-AsciiMath input | B0 contract gates each later phase | estimated in lane B | pending |
| B4 | AsciiMath uncertainty grammar, amath release and Plurimath input integration | A4 and B0–B3; B0 syntax contract | estimated in lane B | pending |

A tasks total **74–128 engineering hours**. Reserve **16–28 hours** separately
for PARG feasibility, diagnostic normalization, Slice migration or package/platform
repair: **90–156 hours including contingency**. This excludes lane B's work,
release authorization and external waiting. Low confidence until A0/A1 pass;
re-estimate downstream items then, retaining the full acceptance scope. Each
phase lists additive task ranges; shared fixture work is counted only in A1.

## Completion and progressive elaboration

#494 completes when the released amath dependency is used by the merged
Plurimath PR with the required suite and parity checks passing. A2 alone is
partial delivery. Preserve accepted/rejected behavior, full consumption,
configuration, typed positioned leaves, transform outputs and ordinary `+-`.
A1 freezes the Parslet oracle; neither engine may define its own expected tree.

A0 and A1 have detailed items now. A2–A4 contain executable scope, paths,
checks and budgets; expand them into numbered tasks after prerequisites pass,
using the signed contract rather than guessing unresolved APIs.

A0 and A1 may run together. B0–B3 can proceed independently with vocabulary
and Slice ownership rules observed. B4 starts after A4; do not implement its
syntax in the parser being removed. Opal implementation is excluded. Decision 8
must resolve retirement timing before A3 removes the plurimath-js update/test
path, with the consumer impact in release notes and the PR.

## Next handoff

Start [A0 contract](a0-contract/01-amath-contract.md) and
[A1 baseline inventory](a1-baseline/01-tree-baseline.md) on their pinned bases.
Record status, delivered revisions, actual command/exit-code evidence and next
action in each item's checklist. Keep unresolved choices pending. Before removing
this plan, preserve contracts and the B4 handoff at the durable destinations
in [cross-cutting](cross-cutting.md#durable-contracts).
