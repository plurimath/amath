# 01 — Define the amath boundary

Status: **pending**. Effort: **4–7 hours**. Dependencies: pinned source in
[cross-cutting](../cross-cutting.md); resolve with A0 spike results before A2.

## Why

amath must load without Plurimath while retaining the tree, configuration and
error semantics its transform expects. Proposed API/options below are design
inputs for A0, not existing symbols or approved defaults.

## Executable work

1. In existing `README.adoc` and proposed `docs/parser-contract.adoc`, specify
   `Amath.parse(input, **options)`, successful tree, rejected-input exception
   and artifact/runtime errors. Inventory external data in existing Plurimath
   `lib/plurimath/asciimath/parser.rb` (`Parser#parse`, preprocessing),
   `parse.rb` (`read_text`, `dynamic_parser_rules`, decimal marker rules),
   `constants.rb` (`Constants.precompile_constants`) and
   `lib/plurimath/base_number_prefix.rb`. Record who supplies each value.
2. Decide decimal API/default and locale resolution, vocabulary ownership, and
   preprocessing placement. Preserve the default and non-default context in both
   number and comma-separated numeric lookahead. Record raw and preprocessed
   strings and delimiter changes; do not silently move positions to raw input.
3. Specify normalized success trees: hash keys, ordered arrays, text, empty
   leaves, leaf types and offsets. Proposed comparison format uses zero-based
   **byte offsets into preprocessed UTF-8 input**; A0 must confirm against
   Parslet and record any mapping for raw-input diagnostics. Record character
   indices separately if needed; never compare unlike units.
4. Specify rejected cases with the same context and a normalized failure
   position. Proposed rule: deepest Parslet failure converted to the same
   zero-based preprocessed-byte coordinate. Validate this on native/Ruby and
   non-ASCII cases before adopting it; resolve any incompatible position policy
   explicitly before A1 freeze. Parser-specific message text/cause-tree layout
   may be excluded, but accepted/rejected status and agreed offset may not.
   Full consumption is required; invalid trailing text cannot become success.
5. Inventory the ten exact-class Slice checks in the five consumer files in
   [ownership](../cross-cutting.md#file-ownership-in-plurimath). Prefer proposed
   `Asciimath::SliceAdapter` in `lib/plurimath/asciimath/slice_adapter.rb` to
   construct actual `Parslet::Slice` objects. Prove text/empty text, offsets,
   `to_s`, `to_str`, `to_sym`, equality and numeric conversions. If infeasible,
   record the exact five migration files and coordinate B's edits; update both
   A3 tasks and the shared table before A3 begins.
6. Choose public engine selection. Proposed policy: `engine: :auto` uses native
   where supported and Ruby only when native is unavailable; `:native` requires
   native and fails if unavailable; `:ruby` explicitly uses Ruby. This requires
   an amath wrapper because Parsanol's `mode: :native` alone is not strict.
   Record the actual engine, detect internal fallback in differential checks,
   and decide how unsupported native constructs are handled without claiming
   native coverage from Ruby execution. Pin supported Ruby/platforms from actual
   CI evidence. A0 may revise this proposal, but must publish the selected policy.
7. Separate unavailable native support from invalid artifacts. Missing file,
   malformed JSON, bad checksum, unsupported artifact shape/version or runtime
   incompatibility must surface explicit errors in all selected modes. No
   artifact error may trigger fallback to another artifact/grammar or silent
   recompilation of an unrelated source. Pure Ruby may rebuild the valid
   artifact's embedded source as Parsanol's documented runtime path.
8. In proposed `docs/extraction-handoff.adoc`, preserve corpus revisions,
   vocabulary/grammar checksums, Slice choice and eventual B4 syntax/semantic
   contract reference; confirm the durable destinations in cross-cutting.

## Done when

- [ ] Public API, normalization, errors, fallback and support matrix are written
      in durable docs; Suleman records decisions 2–3 with rationale/revision.
- [ ] Every external grammar input has a source/default and reproducible context.
- [ ] Slice decision updates one consistent ownership/compatibility contract.
- [ ] Proposed API behavior is covered by the spike, including non-ASCII offsets,
      empty input, raw/preprocessed delimiters and rejected valid-prefix inputs.
- [ ] amath's runtime depends on Parsanol only; no Plurimath require/constants.

Checks are planned: run the proposed spike command in item 02, inspect its
case/engine/offset report, and compare each contract claim with observed results.
No runtime command in this item has yet been implemented or executed.
