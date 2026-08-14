# Parity harness

Runs a table of cases through the real `@casl/ability` and records what it
answers. `packages/casl/test/parity_test.dart` replays the recording, so a
divergence from CASL.js fails the build instead of reaching a user.

This exists because every divergence found in the original audit was found by
running both implementations on the same input, and nothing in either repository
did that on an ongoing basis. The next one would have been found by a user.

## Running it

```bash
cd tool/parity
npm ci          # or `npm install` the first time
npm run generate
```

Writes `packages/casl/test/fixtures/parity.json`. **Commit the result** — it is
the contract, and CI regenerates it to check that nobody edited it by hand.

Then:

```bash
cd packages/casl && dart test test/parity_test.dart
```

## Adding a case

Append to `cases.mjs`. Every case needs a stable `id` — it is what a failure
names, and what a deviation is keyed by, so renaming one loses its history.

```js
{
  id: 'eq/array-value',
  op: 'can',
  rules: [{ action: 'read', subject: 'A', conditions: { tags: ['a', 'b'] } }],
  check: { action: 'read', subject: { type: 'A', value: { tags: ['a', 'b'] } } },
}
```

Regenerate, run the Dart test, and one of two things happens.

**It passes.** The case is now pinned. Nothing else to do.

**It fails.** You have found a divergence. Decide which implementation is right:

- *CASL.js is right* — fix `casl`. The fixture already holds the correct answer.
- *We are right, deliberately* — mark the case as a deviation and say why. A
  deviation with no reason fails the build, on purpose: the reason is the whole
  value of recording it.

```js
{
  id: 'eq/array-value',
  op: 'can',
  rules: [ /* … */ ],
  check: { /* … */ },
  deviates: {
    dart: true,
    reason: 'ucast compares with ===, so CASL.js cannot match an array by '
          + 'value. Ours does what MongoDB does. See docs/PARITY.md D-01.',
  },
}
```

Then add the row to `docs/PARITY.md`. The fixture enforces the decision; the
ledger explains it.

## Operations

| `op` | Asserts on | Extra fields |
|---|---|---|
| `can` | `ability.can(action, subject, field)` | `check` |
| `ast` | `rulesToAST(ability, action, subjectType)` | `action`, `subjectType` |
| `fields` | `permittedFieldsOf(...)` | `action`, `subject`, `allFields` |
| `defaults` | `rulesToFields(ability, action, subjectType)` | `action`, `subjectType` |
| `actions` | `ability.actionsFor(subjectType)` | `subjectType` |
| `pack` | `packRules(rules)` | — |
| `rules` | `possibleRulesFor(action, subjectType).length` | `action`, `subjectType` |

A case that throws on either side records `{"!throws": true}`. We assert only
*that* both throw, never the message — the wording is not a contract, and
pinning it would make every improved error message a failing test.

## Values JSON cannot carry

Two escapes, understood by both sides:

| Dart / JS value | In a case |
|---|---|
| `RegExp('^ab', caseSensitive: false)` | `{ "!re": "^ab", "flags": "i" }` |
| `DateTime.parse('2024-01-01Z')` | `{ "!date": "2024-01-01T00:00:00.000Z" }` |

`cases.mjs` exports `re()` and `date()` so you write `re('^ab', 'i')` rather
than the raw shape.

## Upgrading `@casl/ability`

The version in `package.json` is pinned exactly, because this is a reference
implementation rather than a dependency. To move it:

1. Bump it, `npm install`, `npm run generate`.
2. **Read the fixture diff.** Every changed line is a behaviour change upstream.
3. Decide, case by case, whether to follow. Record anything you do not follow.

That diff is the only place an upstream behaviour change is visible before a
user finds it.
