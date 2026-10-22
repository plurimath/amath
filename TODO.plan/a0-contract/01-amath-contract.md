# TODO 1 — Write amath's contract

## Why
amath has to be usable without Plurimath, and Plurimath has to keep working
without changing its transform. Those two pull in different directions, so the
boundary is written down before any code: what `Amath.parse` takes, what it
returns, and which of today's inputs move into amath versus stay with the
caller.

## Scope
- The call: `Amath.parse(input, **options)` → tree, or a parse error carrying
  the position.
- Options, each with a default that matches Plurimath's default today:
  - decimal marker (today from `Plurimath.configuration`);
  - the symbol vocabulary, or a statement that it ships inside the artifact
    (open decision 2);
  - anything else `parser.rb:9–14` preprocesses before parsing — decide whether
    that preprocessing moves into amath or stays in Plurimath.
- The tree shape: the same hash-and-leaf structure Parslet returns today, so
  `transform.rb` reads it unchanged.
- A `Slice` adapter in Plurimath that turns amath's leaves into real
  `Parslet::Slice` objects before the transform sees them. Ten places depend
  on Parslet slices (six in `transform.rb`, plus `math/number.rb:10`,
  `math/function/unary_function.rb:10`, `utility.rb:213`,
  `asciimath/utility.rb:22`), so converting once at the boundary is safer than
  changing each one. If that proves impossible, list every consumer and move
  the changes into A3's scope explicitly.
- Errors: what a rejected input returns, and that a corrupt or mismatched
  artifact fails loudly instead of falling back.
- Dependencies: amath depends on Parsanol only. No `require "plurimath"`, no
  Plurimath constants.

## Done when
- [ ] The contract is written in amath's `README.adoc` (user-facing part) and
      in this file (internal part).
- [ ] Every input today's parser reads from outside the grammar is listed, with
      where it comes from after the move.
- [ ] The `Slice` choice is made, with its reason, and covers all ten
      consumers.
- [ ] Suleman has agreed it.
