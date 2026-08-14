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

## Releasing

```bash
melos run ci           # green before anything else
melos version          # bumps, writes CHANGELOGs, rewrites constraints, tags
git push --follow-tags
```

That is the whole of it.

`melos version` reads the conventional commits since each package's last tag,
decides the bump, writes the CHANGELOG entry, commits, and creates a
`<package>-v<version>` tag for every package it changed. The step worth having
it do rather than a human: when `casl` moves it rewrites `casl_flutter`'s
`casl:` constraint to match and gives `casl_flutter` its own bump for having
changed. That is the step most easily forgotten, and forgetting it publishes a
`casl_flutter` that resolves against the previous `casl`.

Pushing the tags starts [`publish.yml`](.github/workflows/publish.yml). It
re-checks the tag against the pubspec and the changelog, re-runs `melos run ci`,
waits for any workspace dependency to appear on pub.dev, and then publishes
through pub.dev's OIDC flow — **no long-lived credential exists anywhere**, and
the published version carries provenance back to the commit.

One thing is deliberately not automatic: the publish job pauses for approval on
the `pub.dev` environment. Approve it from the run's page.

### Read what it wrote before you push

Nothing has left the machine until `git push`, so the generated changelog is
still editable:

```bash
melos version
$EDITOR packages/casl/CHANGELOG.md         # lead with the consequence, not the mechanism
git add -A && git commit --amend --no-edit
git tag -f casl-v1.2.3                     # the tag was made before the amend
git push --follow-tags
```

Worth doing for a major, or any release with a migration. A generated entry
says what was committed; a release with a breaking change needs to say what to
do about it, and that belongs in `MIGRATING.md` as well as the changelog.

### When it guesses wrong

`flutter_onboarding` is the standing example — a breaking change landed without
the version moving, so its commit history under-reports the bump:

```bash
melos version --manual-version flutter_onboarding:major
```

### Prereleases

A `casl-v1.1.0-beta.1` tag matches nothing in `publish.yml` and does nothing at
all. That is deliberate: pub.dev's tag-pattern would have to be widened to
match, and a prerelease of an authorisation library is a decision rather than a
convenience. Publish one by hand.

---

## The order, which is now enforced rather than remembered

`casl_flutter` depends on `casl`, and `melos version` tags both in one commit —
so both workflow runs start together with nothing sequencing them. Publishing
`casl_flutter` first would leave a window in which it requires a `casl` that is
not on pub.dev yet, and every fresh `pub get` during that window fails.

`publish.yml` closes that itself: before publishing, it polls pub.dev for each
workspace package the one being published depends on, and waits up to ten
minutes. If `casl`'s own run fails, `casl_flutter`'s waits and then fails too,
which is the right outcome.

This is also why `melos run pana` does not score `casl_flutter`: pana resolves
`casl` from pub.dev rather than from this workspace, so between the two releases
it measures the new `casl_flutter` against the old `casl` and reports failures
that mean nothing. Score it by hand once `casl` is out.

```bash
dart pub global run pana --no-warning packages/casl_flutter
```

---

## Publishing by hand

The fallback, and how a prerelease goes out:

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

---

## One-time setup

None of the above works until this is done, and none of it can be scripted —
pub.dev has no API for it. Steps 1 and 2 are per package, all three.

**1. pub.dev → the package → Admin → Automated publishing.**

Enable *Publishing from GitHub Actions* and set:

| | |
|---|---|
| Repository | `teispace/flutter-packages` |
| Tag pattern | `casl-v{{version}}` · `casl_flutter-v{{version}}` · `flutter_onboarding-v{{version}}` |
| Environment | `pub.dev` |

The tag pattern is the security boundary: pub.dev reads the triggering tag out
of the OIDC token and refuses to publish a package the tag does not name. It has
to say the same thing as the matching line in `publish.yml`.

**2. GitHub → Settings → Environments → `pub.dev`.**

Add the maintainers as required reviewers, and limit deployment branches and
tags to `*-v*`.

This is the control that matters. Without it, **anyone who can push a tag can
publish** — pub.dev's own documentation says so. With it, publishing is a
reviewed action even when the tag was not. Configure it before naming it on
pub.dev, or the first run is rejected.

**3. GitHub → Settings → Rules → Rulesets.**

A tag ruleset targeting `*-v*`, restricting creation to maintainers. Defence in
depth behind step 2, and it fails earlier and more legibly.

Automated publishing cannot create a package — a first version has to go out
with `dart pub publish` by hand. All three are already on pub.dev under the
`teispace.com` publisher, so this does not arise unless a fourth package is
added.
