# Releasing

Maintainers only. Each package is versioned and released on its own — they
share a repository, not a release train.

---

## What counts as breaking

`casl` decides what a user is allowed to do, so the usual "did the signature
change" test is not enough. **A change that makes any rule answer differently is
breaking, whether or not a single call site has to be edited.** A caller who
upgrades and gets a different answer has had their authorisation changed
underneath them, and that is exactly the kind of change nobody notices until it
matters.

| Change | Bump |
|---|---|
| A rule answers differently — in either direction | **major** |
| A signature changes, a name is removed or renamed | **major** |
| A deliberate deviation from `@casl/ability` is added, removed or reversed | **major** |
| Reading a rule now throws where it did not, or stops throwing where it did | **major** |
| A new API, a new operator, a new escape hatch | minor |
| A wider SDK or dependency constraint | minor |
| A narrower one | **major** |
| A defect fixed with no answer changing | patch |
| Documentation, tests, tooling, comments | patch |

Anything in the first block goes in `MIGRATING.md`, not only the changelog. A
changelog entry says what happened; a migration guide says what to do.

**Never breaking, at any version:** the wire format. A rule computed by a
`@casl/ability` server has to keep meaning the same thing here. Changing that
would not be a major version, it would be a different package.

---

## Before you tag

```bash
melos run ci
```

That is format, analyze, test, parity, docs, coverage, pana and a publish
dry-run. Green locally means green in CI. Then, by hand:

- [ ] `CHANGELOG.md` is written **for a reader** — what changed for them, not
      what was committed. Group under `### Added` / `### Fixed` / `### Changed`,
      and lead each entry with the consequence rather than the mechanism.
- [ ] `MIGRATING.md` covers every breaking change, with a `diff` for each.
- [ ] `version:` bumped, and `## Unreleased` renamed to the version.
- [ ] The version in each README's install snippet matches.
- [ ] `git status` is clean. `pub publish` warns about a dirty tree, and it is
      right to: publishing something that is not in a commit means publishing
      something nobody can look up.

---

## The order, which is not optional

`casl_flutter` depends on `casl`. Publish `casl` first, wait for pub.dev to
index it, then bump `casl_flutter`'s constraint and publish that.

This is why `melos run pana` does not score `casl_flutter`: pana resolves `casl`
from pub.dev rather than from this workspace, so between the two releases it
measures the new `casl_flutter` against the old `casl` and reports failures that
mean nothing. Score it by hand once `casl` is out.

```bash
dart pub global run pana --no-warning packages/casl_flutter
```

---

## Publishing

Automated publishing is configured on pub.dev per package, so a tag does it:

```bash
git tag casl-v1.2.3
git push origin casl-v1.2.3
```

The tag name carries the package, because a repository with several versioned
things in it needs tags that are unambiguous. `.github/workflows/release.yml`
matches `<package>-v<version>`, checks the tag against the pubspec, and
publishes through pub.dev's OIDC flow — no long-lived credential exists
anywhere, and the published version carries provenance back to the commit.

If you have to publish by hand:

```bash
cd packages/casl
dart pub publish
```

---

## After

- [ ] The pub.dev score is 160/160. If it is not, the report says why —
      `melos run pana` reproduces it locally.
- [ ] The example still runs against the published version rather than the
      workspace one.
- [ ] Open the next `## Unreleased` heading, so the first person to land a
      change does not have to.
