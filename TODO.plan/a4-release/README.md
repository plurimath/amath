# A4 — Release (#494)

## What it delivers
amath's first release, and the Plurimath PR that depends on it, merged. That
merge is the point #494 is done.

## Why here
Plurimath cannot depend on an unreleased gem in a release of its own.

## Risks and notes
- Release steps (version, changelog, gem push) follow how `mml` and `omml` are
  released; check theirs before writing the item.
- The gem is tested as built, not as checked out: install the `.gem`, load the
  artifact from it, parse.
- Both the gem release and the PR are remote writes and need approval at the
  time.

## Exit criteria
- [ ] amath released; installing the published gem and parsing works.
- [ ] Plurimath PR depends on the released version and passes the full suite.
- [ ] PR merged. → **#494 done.** B4 can start.
