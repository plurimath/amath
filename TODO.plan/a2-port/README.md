# A2 — Grammar port (#494)

## What it delivers
The full AsciiMath grammar in `plurimath/amath`: `grammars/asciimath.parg`, the
compiled artifact with its checksum, the conformance corpus from A1, the
`Amath.parse` gem from A0's contract, and `scripts/check.rb` that rebuilds the
artifact and replays the corpus.

## Why here
After A0 shows the hard parts work and A1 freezes what "correct" means, the
port is transcription against a gate, not design.

## Risks and notes
- `parse.rb` on `main` is 234 lines with 38 rules, plus the rules generated
  from Ruby tables and from `base_number_prefix.rb`. The generated part is
  bigger than the hand-written part.
- Rewriting constructs PARG rejects can change which inputs are accepted. The
  corpus's rejected cases catch that.
- plurimath-ts ported this grammar to pegkit; its notes on the grammar's quirks
  save rediscovery.
- Gem metadata follows `plurimath/omml`: authors "Ribose Inc.", email
  open.source@ribose.com, BSD-2-Clause. Minimum Ruby comes from the pinned
  Parsanol release, not from omml.

## Exit criteria
Work items are written when A0 and A1 finish. The gate they will serve:
- [ ] Every corpus case gives an identical tree on both Parsanol engines.
- [ ] Every corpus case, put through Plurimath's unchanged transform, gives
      identical output.
- [ ] The artifact loads from the built gem, and a wrong checksum fails loudly.
