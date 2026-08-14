# Contributing

Thanks for looking. Bug reports and pull requests are both welcome, and a
failing test is the most useful thing you can send.

Before anything else: this repository has a
[Code of Conduct](./CODE_OF_CONDUCT.md), and a permission check that returns the
wrong answer is a **security issue** — report those through the
[security policy](./SECURITY.md), not a public issue.

---

## Getting set up

```bash
dart pub global activate melos
melos bootstrap
melos run ci
```

`melos run ci` is the pipeline CI runs — format, analyze, test, parity, docs,
coverage, pana, publish dry-run. Green locally means green there. `melos run`
on its own lists every script with what it does.

Three of those steps need something beyond the Flutter SDK:

```bash
dart pub global activate coverage   # melos run coverage
dart pub global activate pana       # melos run pana
# and Node 22+, for melos run parity
```

### Running one thing

```bash
melos run analyze                      # every package
melos run test                         # every package
cd packages/casl && dart test          # one package
cd packages/casl && dart test test/parity_test.dart
cd packages/casl_flutter && flutter test

melos run docs:check                   # compile every README snippet
melos run parity                       # regenerate and diff the fixtures
```

---

## The one thing that makes this repository different

`casl` is a port. Its whole value is that a rule computed by a
`@casl/ability` server and evaluated by a Dart client **means the same thing**.
Authorisation duplicated across two languages drifts, and the drift is invisible
until somebody sees a button they should not have.

So we do not assert parity by reading the JavaScript. We run it.

### The parity harness

`tool/parity/` walks a table of cases through a pinned `@casl/ability` and
records what it answers. `packages/casl/test/parity_test.dart` replays the
recording.

```bash
cd tool/parity
npm ci
npm run generate     # writes packages/casl/test/fixtures/parity.json
```

**Commit the regenerated fixture.** CI regenerates it and fails on any diff,
which catches both a fixture edited by hand to make a test pass and an upstream
behaviour change — neither of which any Dart test could otherwise see.

### Adding a case

Append to `tool/parity/cases.mjs`, regenerate, run the Dart test. Ids are
stable identifiers rather than descriptions: a failure names one, and renaming
one loses its history.

```js
{
  id: 'op/size-nested-array-path',
  op: 'can',
  rules: [{ action: 'read', subject: 'A', conditions: { 'items.tags': { $size: 2 } } }],
  check: { action: 'read', subject: of_('A', { items: [{ tags: [1, 2] }] }) },
}
```

`tool/parity/README.md` has the full format — the operations, and the two
escapes for values JSON cannot carry (`RegExp` and `DateTime`).

### When a case fails

You have found a divergence. It is one of three things, and saying which is the
actual work:

**1. We are wrong.** Fix `casl`. The fixture already holds the right answer.

**2. We are deliberately different.** Mark it, with a reason. A deviation with
no reason fails the build, on purpose — the reason is the entire value of
recording it.

```js
deviates: {
  dart: false,
  reason: 'JavaScript coerces across types, so `"10" > 3` is true. We refuse '
        + 'to order values we cannot compare, because a condition comparing a '
        + 'string to a number is a mistake and denying is the safe reading of '
        + 'a mistake. See docs/PARITY.md D-12.',
}
```

**3. We are wrong, and it is not fixed yet.** Mark it `pending` with the finding
id it is tracked under.

```js
pending: 'D-08',
```

A pending case asserts that the divergence **still exists**. That looks
backwards and is the point: the day somebody fixes it, the test fails and tells
them to clear the marker. A plain skip would let the bookkeeping rot.

---

## Opening a pull request

- **One package per PR** where you can. They are released independently, and a
  change spanning two is harder to revert than two changes spanning one each.
- **Add the test that would have caught it.** Not just a test — the one that
  fails on the parent commit. A change that cannot be tested is worth a
  sentence in the PR saying why.
- **Add a CHANGELOG entry** under `## Unreleased`, in the package you changed.
  Do not bump `version:` — that happens at release, when it is known which
  changes are going out together.
- **Conventional Commits**, scoped to the package: `fix(casl): …`.
- **Document what you export.** `public_member_api_docs` is on, so this is
  enforced rather than requested. Write it for a reader, not for the linter.

### If it touches authorisation behaviour

Say **which direction it moves us**: more permissive, more restrictive, or no
change to any outcome.

A permissive change gets read twice. A client that allows what its server
refuses renders a control the API will reject, which is the exact failure these
packages exist to prevent — so "we are more correct than CASL.js" is never
sufficient on its own.

---

## House style

The code here is written to be read, and reviews will say so.

- **Comments explain why, never what.** A comment restating the line below it is
  noise; one recording a constraint, a measured finding, or an alternative that
  was tried and rejected is the point.
- **Tests prove failure, not just success.** A test that only walks the happy
  path tells you the code runs, not that it is right.
- **`casl` depends on `meta` and nothing else.** Every dependency is a reason
  somebody cannot adopt an authorisation library. Adding one is a decision, not
  a convenience.
- **No code generation.** A build-time dependency here would tie rule names to
  Dart identifiers rather than to the names the server writes rules about.

---

## What gets a change rejected

Only three things, really:

1. A public API change with no path forward for people already using it.
2. A behaviour change with no test pinning it.
3. A change to what a rule means, with no parity fixture and no ledger entry.

All three are usually fixable in review rather than fatal. Say what you are
trying to do and it can be worked out.

---

## Reporting a bug

Use the [issue templates](https://github.com/teispace/flutter-packages/issues/new/choose) —
they ask for the package version, the SDK version, and the rules, because those
are the first three things anyone will ask for anyway.

There is a dedicated **parity gap** template for "CASL.js does X and you do Y".
That is the report we most want.

---

## Releasing

Maintainers only — see [RELEASING.md](./RELEASING.md), which covers what counts
as a breaking change (in an authorisation library that is a wider question than
usual), the checklist, and why `casl` has to go out before `casl_flutter`.
