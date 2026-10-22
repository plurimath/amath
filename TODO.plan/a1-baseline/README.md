# A1 — Freeze the parity oracle

Status: **pending**. A1 captures the unmodified Parslet behavior at Plurimath
`ae20be111a26fdd988c58be0bfb2b7f6fe6e352f`; it may run beside A0. Freeze only
after A0 resolves leaf/error normalization and vocabulary/context semantics.

| Item | Result | Status |
|---|---|---|
| [01 — Tree baseline](01-tree-baseline.md) | Typed positioned successes, rejects and context manifest | pending |
| [02 — Output replay](02-output-replay.md) | Schema-aware replay passing on the pinned oracle | pending |

These fixtures and scripts are reused by later phases.

The shared testsuite has 27 AsciiMath payload files with string-only parse trees.
It is input to A1, not a typed/positioned oracle. Add every AsciiMath input in
Plurimath's own specs, preserving test context, expected rejection and formatter
arguments. Pin provenance and checksums rather than assuming every case has six
ordinary serializer outputs. Ordinary `+-` remains `Math::Symbols::Pm` after
both lanes land.

## Exit criteria

- [ ] Typed baseline and schema/context manifest regenerate byte-identically.
- [ ] Rejected cases, agreed offsets and full-consumption controls are included.
- [ ] Vocabulary behavior fingerprint detects category/order changes.
- [ ] Output replay passes on the original oracle before judging new code.
- [ ] Record case counts by outcome/schema, source pins, command and exit code.

Next: inventory source specs and schema versions, then implement item 01's
generator without changing the oracle. No baseline behavior run is yet claimed.
