# TODO 1 — Record today's parse trees

## Why
The testsuite does record parse trees, but its generator turns every leaf into
a plain string (`scripts/generate-corpus.rb:571`, per Codex), losing leaf types
and positions. Keeping `transform.rb` unchanged depends on exactly those, so
the tree needs a record that keeps them. It also covers only the shared
corpus, not every input in Plurimath's own specs.

## Scope
- Collect every AsciiMath input from Plurimath's specs
  (`spec/plurimath/asciimath/**`, `spec/plurimath/asciimath_spec.rb`, and other
  specs that parse AsciiMath) and from plurimath-testsuite's
  `corpus/asciimath/`.
- For each input, record:
  - the input and the context it needs (decimal marker, locale, options);
  - the input after `parser.rb`'s preprocessing;
  - accepted or rejected, and for rejections the error position;
  - the Parslet tree, serialised with leaf types and positions kept;
  - the base commit, Ruby version and gem versions.
- A small script that regenerates the file and refuses to run on a dirty tree,
  so the baseline can be rebuilt and checked.
- The vocabulary fingerprint (sorted word list → SHA-256).

## Done when
- [ ] The baseline file and its generator exist, with the case count measured.
- [ ] Rerunning the generator on `ae20be11` gives a byte-identical file.
- [ ] Rejected inputs and context-dependent inputs are included, not just
      happy paths.
- [ ] Where it lives is decided: amath's `corpora/` (it is the port's
      conformance corpus) — confirm with open decision 1.
