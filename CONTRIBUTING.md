# Contributing

Thanks for looking. Bug reports and pull requests are both welcome.

## Getting set up

```bash
dart pub global activate melos
melos bootstrap
melos run ci
```

`melos run ci` is the same pipeline CI runs — format, analyze, test, and a
publish dry-run of every package. If it is green locally it is green there.

## Opening a pull request

- **One package per PR** where you can. They are released independently, and a
  change spanning two is harder to revert than two changes spanning one each.
- **Add a test.** Every package here has a suite; a change that cannot be
  tested is worth a sentence in the PR saying why.
- **Add a CHANGELOG entry** under `## Unreleased`, in the package you changed.
  Do not bump `version:` — that happens at release, when it is known which
  changes are going out together.
- **Conventional Commits**, scoped to the package: `fix(casl): …`.
- **Document what you export.** `public_member_api_docs` is on, so this is
  enforced rather than requested.

## What gets a change rejected

Only two things, really: a public API change with no path forward for people
already using it, and a behaviour change with no test pinning it. Both are
usually fixable in review rather than fatal — say what you are trying to do
and it can be worked out.

## Reporting a bug

Please include the package and its version, the Flutter or Dart version, and
the smallest snippet that reproduces it. A failing test is the ideal bug
report and is very often the fastest fix.

## Releasing

Maintainers only, and one package at a time:

1. Bump `version:` and turn `## Unreleased` into the version heading.
2. `melos run publish:check`.
3. `dart pub publish` from the package directory.
4. Tag `<package>-v<version>`, so tags stay unambiguous in a repository with
   several versioned things in it.

`casl_flutter` depends on `casl`. Releasing both means publishing `casl` first
and letting pub.dev index it before the second goes out.
