# Decisions and blocking points

All rows in the open table are pending; proposals are not approvals. Record
outcome, public rationale and durable contract revision when resolved. The
original plan records the settled scope below; no additional approval is inferred.

## Open

| # | Decision | Owner | Blocks | Proposed resolution / evidence needed |
|---|---|---|---|---|
| 1 | Gem and grammar repository layout | Ronald | A2 | Keep grammar/artifact in amath as #494 requests; confirm after spike. |
| 2 | Caller or artifact vocabulary; category/order fingerprint and generated tables | Suleman from A0 | A1 freeze, A2 | Compile/reload both feasible candidate boundaries; select one without a Plurimath dependency. |
| 3 | Decimal/configuration, preprocessing, error offsets, Slice and engine support contract | Suleman from A0 | A1 normalization freeze, A2; ownership before A3 | Proposed keywords and boundary adapter; prove under both engines, non-default locale and non-ASCII input. Record byte/character and raw/preprocessed mapping. |
| 4 | Required uncertainty forms, per-language minimums and precise semantic payload | Ronald via B0 | B1–B4 contract | Standard, concise, expanded and asymmetric proposals need field/validation examples and required-format floor; no automatic approval of all variants. |
| 5 | Plain ± versus uncertainty in each input language | Ronald via B0 | B3, B4 | Record explicit syntax; preserve ordinary `+-`. |
| 6 | LaTeX input or output only | Ronald via B0 | B3 | Output first is a proposal; optional input does not substitute for four required languages. |
| 7 | UnitsML attachment and separately any dependency work | Ronald via B0 | B1 model; selected work in B2–B4 | Choose unit representation or approved exclusion. If dependency work needed, B owns base/tag, tasks, release and preservation checks. No B5. |
| 8 | Timing of retiring plurimath-js update/test path | Ronald | A3 | Opal implementation remains excluded. Before deletion record accepted consumer impact, retirement timing and PR/release note text; align A3 diff with outcome. |
| 9 | All #430 overlap and migration order | Suleman | A3; overlapping B3 work | Proposed AsciiMath superseded by A; proposed LaTeX retained later. Decide HTML/UnicodeMath, shared Slice and direct Parslet dependency changes separately: deferred, superseded, or retained with destination/owner/base. |

Decision 9 is a coordination decision before A3, not a requirement to rewrite
or merge #430 first. Its proposal to narrow #430 to LaTeX is unapproved until
recorded. Select one baseline and migration order for both lanes. Keep Parslet
while the adapter or any unmigrated parser uses it. This plan does not require
remote edits to #430 now.

## Recorded scope

- The lanes run in parallel; uncertainty's AsciiMath input waits for extraction.
- #494 finishes when the Plurimath PR merges with the full suite passing.
- Opal support is excluded; plurimath-ts is intended to replace plurimath-js.
  Retirement timing remains decision 8.
- The existing amath repository starts from `8a15303` (README only).

## Handoff

Next: A0 resolves decisions 2–3 and prepares decision 1 evidence; B0 resolves
4–7 and commits its durable contract. Before A3, resolve 8–9 and reconcile the
Slice consumer ownership list. Carry resolved facts into the maintained docs
listed in [cross-cutting](cross-cutting.md#durable-contracts), not only this table.
