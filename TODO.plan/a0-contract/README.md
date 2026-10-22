# A0 — Contract and feasibility

Status: **pending**. A2 waits for a passing spike and the recorded contract.
A1 inventory can proceed alongside A0, but cannot freeze unresolved normalization
or vocabulary semantics.

## Deliverables and tasks

| Item | Files / result | Effort (hours) | Status |
|---|---|---|---|
| [01 — Contract](01-amath-contract.md) | Existing `README.adoc`; proposed `docs/parser-contract.adoc`, `docs/extraction-handoff.adoc`; shared ownership decision | 4–7 | pending |
| [02 — Spike](02-feasibility-spike.md) | Proposed disposable grammar and differential checks; compiler/dependency evidence | 8–13 | pending |

Total **12–20 hours**, including investigation and focused validation. The prior
informal one-day spike describes only a small probe, not end-to-end delivery.
Contingency is counted once in the overview.

## Why this gates the port

The oracle's `lib/plurimath/asciimath/parse.rb` has captured-delimiter `read_text`,
a configuration-dependent decimal marker used in both `number` and numeric-list
lookahead, generated symbol alternatives, and an empty alternative in
`expression`. A compile success alone does not establish semantic parity.
`Parsanol::Slice` also differs from `Parslet::Slice`; class-sensitive consumers
need a proven adapter or explicit migration scope.

Parsanol's inspected `Artifact#parse(mode: :native)` can execute Ruby when native
is unavailable. The spike must observe actual execution. Pin a released PARG
capable dependency based on the experiment, rather than treating an inspected
main SHA as a release. Both inspected gemspecs establish Ruby >=3.2; effective
platform/CI coverage remains to discover.

## Exit criteria

- [ ] Contract and A3 Slice ownership are recorded; decisions 2–3 resolved.
- [ ] Spike passes both actual engines against the Parslet oracle, including
      rejection/error positions and full consumption.
- [ ] Missing/invalid artifacts and absent-native behavior match the selected policy.
- [ ] Decision 1 evidence and durable contract destinations are recorded.

On a failed hypothesis, record its reproducer and supported alternative; A2
remains blocked until the revised approach has its own passing spike. Do not
waive parity or silently redefine accepted input to make the port feasible.
Next: implement the proposed spike driver only after writing the comparison contract.
