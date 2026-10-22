# A4 — Verify the distribution and release

Status: **pending**. Starts after A3 passes. #494 is complete only after the
Plurimath PR uses a released amath and merges with the full suite passing.

## Work

| Task | Files / result | Status |
|---|---|---|
| Build/install and support-policy proof | amath `amath.gemspec`, proposed `scripts/check_installed_gem.rb`, `docs/parser-contract.adoc`, `docs/extraction-handoff.adoc` | pending |
| Release/dependency propagation and durable handoff | amath version/changelog paths discovered from selected release convention; Plurimath `plurimath.gemspec`, `Gemfile` and maintained uncertainty contract link | pending |

Discover the mml/omml release
convention and name actual version/changelog/tag commands before expanding this
item; do not invent an existing release task. Release and issue closure require
their own authorization; planning does not publish anything.

## Installed-gem acceptance

After implementing A2's proposed script, run in amath:

```sh
gem build amath.gemspec
bundle exec ruby scripts/check_installed_gem.rb --gem "$AMATH_GEM" --native required
bundle exec ruby scripts/check_installed_gem.rb --gem "$AMATH_GEM" --native absent
```

`AMATH_GEM` names the exact built package. These script options are **proposed**
and must be implemented with usage text. The script creates an isolated install
and child processes, removes checkout paths from load paths, and loads only the
installed gem. The required job runs on a supported native-capable platform;
the absent job deliberately makes native unavailable using a documented test
seam in proposed `lib/amath/parser.rb` that cannot change production defaults.
An environment without the extension may be used instead. Do not infer absence
from a flag that leaves the extension available.

Assert the signed automatic/native/Ruby policy, recording actual engine and
installed artifact location. Explicit Ruby and native where supported must
retain full A1 success/rejection/position parity. Automatic mode in no-native
environment must exhibit the documented fallback or error; strict native must
fail if selected by A0's policy. Missing file, malformed JSON, bad checksum,
unsupported artifact shape and incompatible runtime must fail loudly across
supported modes. Corrupt disposable copies of the installed gem only. Run
outside the checkout with the packaged tables/imports/embedded sources present;
no accidental development file access may satisfy the check.

After authorized publication, install the exact published version into a fresh
isolated environment and repeat the same verifier, allowing a proposed
`--version "$AMATH_VERSION"` input instead of `--gem`. Record released version,
artifact hash, platform, Ruby/dependency versions, engine evidence and exit codes.
Only then replace Plurimath's temporary git dependency with the released minimum
and run existing `bundle exec rake spec` plus A1's replay on that actual gem.

## Durable B4 handoff and completion

- [ ] Built and published package tests prove the selected engine/failure policy
      on the documented actual Ruby/platform matrix; limitations stated.
- [ ] Released dependency passes Plurimath full suite, A1 replay and required CI.
- [ ] Commit `README.adoc`, `docs/parser-contract.adoc` and
      `docs/extraction-handoff.adoc` before removing plan scaffolding.
- [ ] Handoff records immutable A4 tag, Plurimath merge SHA, corpus/testsuite pins,
      vocabulary fingerprint and Slice decision. Link B0's signed syntax/semantic
      contract if resolved; otherwise record its B-owned decision blocker. An
      unresolved B0 blocks B4, not completion of extraction A4.
- [ ] Verify the handoff remains usable without feature branches or TODO files.
- [ ] Plurimath PR merged: #494 acceptance complete. Do not close #493 here.

B4 then rebases Plurimath onto A4's merged main and branches amath from its A4
release. B owns grammar/artifact changes, uncertainty captures and transform,
new amath release and Plurimath minimum bump. Gate B4 against all A1 compatibility
cases plus independent B0-required uncertainty examples for each supported
semantic variant; plain ±/algebra/parentheses must remain unchanged. Keep the
B0 required-language minimum and loss contract in `docs/uncertainty.adoc` after
B's plan is removed. B4 release work is counted in lane B, not A4.
