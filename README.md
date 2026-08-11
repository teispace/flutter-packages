# Teispace Flutter packages

The Dart and Flutter packages we publish, in one repository.

| Package | | What it is |
|---|---|---|
| [`casl`](packages/casl) | [![pub](https://img.shields.io/pub/v/casl.svg)](https://pub.dev/packages/casl) | Isomorphic authorisation. Define what a user may do as rules, ask `ability.can(...)`, and share the exact same rules with a CASL.js backend. Pure Dart. |
| [`casl_flutter`](packages/casl_flutter) | [![pub](https://img.shields.io/pub/v/casl_flutter.svg)](https://pub.dev/packages/casl_flutter) | Flutter bindings for `casl`: an ability in the widget tree, a `Can` widget, and `context.can(...)`. |
| [`flutter_onboarding`](packages/flutter_onboarding) | [![pub](https://img.shields.io/pub/v/flutter_onboarding.svg)](https://pub.dev/packages/flutter_onboarding) | A one-time animated onboarding flow: pages, a dots indicator, and a "seen it" flag persisted for you. |

> `flutter_onboarding` 2.0.0 is staged in this repository and not yet
> published — see its CHANGELOG for what changes for callers.

Each package is published on its own and versioned on its own. They share a
repository, not a release train.

---

## Working on them

```bash
dart pub global activate melos
melos bootstrap      # resolves the whole workspace at once
melos run ci         # format, analyze, test, publish dry-run
```

`melos run` on its own lists every script with what it does.

This is a **pub workspace**, not a set of path dependencies. One resolution,
one lockfile, one `.dart_tool` — so `casl_flutter` develops against the `casl`
in this checkout rather than the version on pub.dev, and there is nothing to
remember to change before publishing.

Each package declares `resolution: workspace`. That field is harmless in a
published package: pub ignores it for a dependency, so a consumer resolves
normally. It has been verified rather than assumed.

### Adding a package

1. `packages/<name>/`, with its own `pubspec.yaml`, `README.md`, `CHANGELOG.md`
   and `LICENSE`.
2. Add it to `workspace:` in the root `pubspec.yaml`.
3. `analysis_options.yaml` containing `include: ../../analysis_options.yaml`,
   so there is one definition of what counts as correct here.
4. `melos bootstrap && melos run ci`.

---

## Conventions

- **Every package documents its whole public API.** `public_member_api_docs` is
  on. These are libraries other people depend on, so the exported surface is
  the product.
- **Comments explain why, never what.** A comment restating the line below it
  is noise; one recording a constraint, a measured finding or a rejected
  alternative is the point.
- **Tests prove failure, not just success.** A test that only walks the happy
  path tells you the code runs, not that it is right.
- **No lockfiles.** A library must resolve against whatever its consumer
  already has. Applications commit `pubspec.lock`; nothing here is one.
- **Commits follow [Conventional Commits](https://www.conventionalcommits.org),**
  scoped to the package they touch — `feat(casl): …`.

## Releasing

Each package is released independently:

1. Bump `version:` in its `pubspec.yaml` and add a `CHANGELOG.md` entry.
2. `melos run publish:check` — a dry run of every package.
3. `dart pub publish` from the package directory.

`casl_flutter` depends on `casl`, so a release that moves both publishes
`casl` first and waits for pub.dev to index it.

---

## Licence

MIT, for every package here. See [LICENSE](LICENSE).
