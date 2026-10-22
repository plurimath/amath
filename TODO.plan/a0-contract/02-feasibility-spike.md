# TODO 2 — Feasibility spike

## Why
The contract says what amath should do; this proves PARG can do it. The spike
covers only the four constructs that are not plain grammar. If one of them
cannot be expressed, we learn it here, on fifty lines, not in the middle of the
full port.

## Scope
- A throwaway PARG grammar in the amath working copy (not pushed) covering:
  1. text read up to the bracket that matches one captured earlier
     (`parse.rb:194–198`);
  2. a configurable decimal marker (`parse.rb:219–220`);
  3. a word list supplied the way the contract says (generated table, shipped
     or passed in), including longest-match ordering;
  4. an empty alternative rewritten so PARG accepts it, with the same accepted
     inputs as `parse.rb:177`.
- Compile it, save the artifact, reload the artifact from disk, and parse with
  it. A grammar that only works before it is saved does not count.
- Pin a Parsanol version that supports PARG, and record it.
- Run the same inputs through **both** Parsanol engines (native and pure Ruby)
  and compare the trees. Record which engine actually ran for each parse, and
  fail if native silently fell back to Ruby — otherwise the comparison is Ruby
  against itself.
- Inputs: a few cases per construct from today's specs, plus one long input
  (over 2,048 characters) and inputs with non-ASCII symbols.
- Compare each tree with what today's Parslet parser gives for the same input.

## Done when
- [ ] All four constructs compile, reload from the artifact and parse.
- [ ] Native and pure-Ruby trees are identical for every spike input, with
      evidence that each engine really ran.
- [ ] Spike trees match today's Parslet trees for every spike input, or each
      difference is explained and has a planned fix.
- [ ] The result is written up here, with the commands, Parsanol version and
      exit codes.
- [ ] If anything fails, this item stays open and A0 is blocked. The failure is
      written up and taken to Ronald; A2 waits.
