# Changelog

## 1.0.0 · 2026-08-14

There are breaking changes. [`MIGRATING.md`](./MIGRATING.md) walks through them;
the two that touch real call sites are `can.each` and, in `casl_flutter`,
`CanResult.reason`. **Nothing about the wire format changed** — rules a server
sent to 0.1.0 mean the same thing now.

### Added

- **Typed abilities.** `Ability`, `AbilityBuilder`, `defineAbility`,
  `permittedFieldsOf`, `rulesToFields`, `rulesToAst`, `AccessibleFields` and the
  `ForbiddenError` guard are now generic over an action type and a subject type,
  both bounded by `String`:

  ```dart
  extension type const AppAction(String wire) implements String {
    static const read = AppAction('read');
    static const update = AppAction('update');
  }

  typedef AppAbility = Ability<AppAction, AppSubject>;

  ability.can('reed', article);   // no longer compiles
  ```

  Extension types erase completely, so this costs **nothing**: a typed action
  *is* a string at runtime, not one byte changes on the wire, there is no
  conversion per check, and rules from a server need no adaptation — including
  rules mentioning actions the vocabulary has never heard of, which still index
  and still deny.

  **Existing code is unaffected.** With no type arguments everything infers as
  `Ability<String, String>`, which is exactly what it was.
- **`defineAbility`** and **`defineAbilityAsync`** — the compact form CASL's own
  guide, cookbook and testing pages use in nearly every example. The two
  callback parameters are just `can` and `cannot`, so name them `allow` and
  `forbid` if that reads better where you are.
- **`AbilityBuilder` takes a factory**, as `new AbilityBuilder(createMongoAbility)`
  does in CASL.js. `build(create:)` still overrides it for one call.
- **`ForbiddenError.from(ability).setMessage(...).throwUnlessCan(...)`** — the
  chain CASL's documentation uses throughout. `setMessage` returns a new check
  rather than mutating, so a shared base cannot change underneath whoever holds
  it. `ForbiddenError.setDefaultMessage` and `resetDefaultMessage` too.
- **`ForbiddenError.ability`**, the ability that refused.
- **`AccessibleFields`** — `permittedFieldsOf` with the ability, the action and
  a field source held once, for a repository that asks per row.
- **`RuleRef.because` is chainable**, matching CASL.js's `RuleBuilder`.
- **`Ability.update` returns the ability**, and the update event carries
  `target` alongside `ability` — v7 renamed the field and deprecated the old
  spelling, so both work here.
- `Unsubscribe` and `AbilityUpdateListener` typedefs.
- **`strictJsEquality`** on `createMongoAbility`. We match nested objects and
  whole arrays by value, as MongoDB does; `@casl/ability` compares with `===`
  and so cannot match them at all. Ours is the more correct answer but the more
  permissive one, so this switches to theirs exactly when a CASL.js server is
  the authority.
- **`onUnparsableCondition`** on `createMongoAbility` and `MongoQueryParser`.
  An operator this client does not know throws by default, which is right for
  rules written in Dart. `UnparsableCondition.deny` makes such a rule grant
  nothing instead — right for rules arriving from a server that may have moved
  ahead of the app.
- **`ConditionFormatException`**, carrying the field and operator at fault.
  Condition parsing used to throw bare `ArgumentError`s and `UnsupportedError`s
  that said nothing about *which* rule was wrong.
- **`OperatorCall.refuse`**, so a custom operator honours the same policy as a
  built-in one rather than throwing past it.
- **`RuleIndex.cachedLookupCount`**, so the cap below can be tested rather than
  asserted.
- **The operator tables are data, not a switch.** `ConditionInterpreter` now
  takes `fieldOperators` and `compoundOperators` maps and has a `withOperators`
  that composes, and `mongoConditionsMatcher` and `createMongoAbility` take an
  `interpreter`. Adding an operator CASL leaves out is a parser entry and an
  interpreter entry — about twenty lines, tested from outside the package.
  Previously the evaluation side was a `final class` with a hardcoded switch, so
  a new operator could be *parsed* and never *evaluated*.
- **`logicalOperators`** — `$and`, `$or`, `$nor` and `$not`, ready to switch on.
  Off by default, because the default set matches CASL.js exactly; on if your
  server already sends them, because refusing a rule the server evaluates is
  worse than either position on whether the operator is good style.
- **`ConditionInterpreter.valueOf`, `parentOf`, `matchesValue`, `includes` and
  `anyOf`** — the helpers a custom operator needs, so it does not have to reach
  past a caller's own field reader or equality to get at a value.
- **`RuleIndex.validateRules`** compiles every rule's conditions at a point you
  choose. Conditions compile lazily, and more lazily than it looks — a rule
  checked only against a subject *type* never compiles them at all — so a rule
  this build cannot read can pass `can('read', 'Article')` and only throw when
  somebody opens a list. Call it after taking rules from a server, where the
  failure is still yours to handle.

### Fixed

- **`RawRule.fromJson` and `unpackRules` now fail with a `FormatException`,
  always.** They used to leak whatever went wrong underneath — an
  `ArgumentError` from the one-or-many normaliser, and for a non-string
  `reason` a bare `TypeError` from an `as` cast. Neither is something a caller
  can be asked to catch: an `Error` means "a programmer wrote this wrong", and
  there is no programmer involved in a payload off a network.
  `ConditionFormatException` is now a `FormatException` too, so a single
  `on FormatException` covers everything that can go wrong reading rules.
- **An empty `fields` list is rejected where it is written**, rather than
  several frames later when the ability is built. A server sending
  `"fields": []` used to crash the client at `createMongoAbility` time with an
  error about a rule it could not point at.
- **A rule reached through both a specific and a wildcard index entry is no
  longer counted twice.** A rule written as
  `RawRule.of(action: ['read', 'manage'], subject: 'Article')` — or with `all`
  among its subjects — was indexed under both keys and met twice when the two
  buckets were merged. `can` was unaffected, but `rulesToCondition` emitted a
  duplicated branch and every check on such a rule paid for the extra entry.
- **A listener may now unsubscribe while it is being called.** Doing so threw
  `ConcurrentModificationError`, because the listener list was walked live. The
  case is not exotic: a permission change that tears down a widget disposes it,
  and disposal is where an unsubscribe lives.
- **A custom `detectSubjectType` no longer disables `subject()` and
  `CaslSubject`.** Returning null fell back to `runtimeType.toString()` rather
  than to the full default, so supplying a detector for one of your own models
  silently switched off the two mechanisms this package recommends. Returning
  null now defers to `detectSubjectTypeByRuntimeType`.
- **`{'a.b': null}` no longer matches an object with no `a` at all.** Mongo's
  `null` means "absent, or present and null" — but of something that could have
  carried the field. `@casl/ability` agrees; we were the more permissive of the
  two, which is the direction that lets a client show a control its server will
  refuse.
- **The examples in the library and `AbilityBuilder` documentation now
  compile and run.** One passed `conditions:` as a named argument where it is
  positional; the other called `build()` on rules carrying conditions, which
  threw.
- **`$size` across a nested array path** measured the flattened result rather
  than each element's own list, so `{'items.tags': {r'$size': 2}}` missed
  `{'items': [{'tags': [1, 2]}]}`.
- **A `RegExp` inside `$in`** was compared for equality instead of being
  applied, so it could only ever match another pattern.
- **Nulls were dropped when reading a path through a list.** JavaScript skips
  only `undefined`, and JSON has no `undefined` — so every null a server sent
  was being discarded.
- **A field query whose `$`-operator was not its first key** was read as a
  literal value and silently matched nothing. Whether the mistake was caught
  depended on the order somebody happened to type the keys.
- **`$options` no longer rejects `g`, `y` and `d`.** They are legal in
  JavaScript and change nothing about a single match, so a rule carrying one
  was being refused even though its own server evaluates it happily. Flags that
  *would* change what a pattern means are still refused.
- **`RawRule.fromJson` now reads `"inverted": 1` as `true`.** It required
  exactly `true`, so a lax server could turn a forbidding rule into a
  permitting one — silently, and in the dangerous direction. `unpackRules` has
  always accepted both.
- **Operator detection no longer depends on the map's static type.** A
  `Map<dynamic, dynamic>` — what `Map.from` and some decoders produce — was
  read as a literal value rather than a query, with no error and a wrong
  answer.

### Changed

- **The export surface is narrower.** Ten ordinary English words are no longer
  in your namespace after `import 'package:casl/casl.dart'`:

  | Was | Now |
  |---|---|
  | `readField`, `readPath`, `readParent`, `hasField` | `CaslFields.read`, `.path`, `.parent`, `.has` |
  | `alwaysTrue`, `alwaysFalse` | `Condition.always`, `Condition.never` |
  | `Subject` | `ForcedSubject` |
  | `oneOrMany`, `subjectValue`, `isSubjectType` | removed — internal chores that leaked |

  `Subject` is the one that mattered: it collides with `rxdart`'s, and an
  unused collision is fine right up until somebody uses it. The rest are names
  an application is quite likely to want for itself, and a package that forces
  `hide` clauses on a common import is a package people put down.
- **`AbilityBuilder.can` and `cannot` are callable objects rather than
  methods.** `can('read', 'Article')` is unchanged; the many-action form moved
  from `can(['update', 'delete'], …)` to `can.each(['update', 'delete'], …)`.
  CASL.js overloads that first parameter on whether it is given a string or an
  array — Dart cannot, and typing it `Object` to fake it would throw away the
  point of typing it at all.
- **`AbilityGuard.throwUnlessCan` no longer takes a trailing `message`.** It
  needed a `null` placeholder for `field` to reach, and
  `ForbiddenError.from(ability).setMessage(...)` now says the same thing
  properly. `errorUnlessCan` keeps the parameter.
- **`AbilityBuilder.build()` now defaults to `createMongoAbility`** instead of a
  bare `Ability`. The old default had no conditions matcher, so any rule with
  conditions failed at `build()` time with an error about an option the caller
  had never heard of. Pass `create:` for anything else; behaviour is unchanged
  for rules without conditions.
- `createMongoAbility`'s `detectSubjectType` parameter is now named
  `PartialDetectSubjectType`, and its "return null to defer" contract is
  documented rather than implied.

### Performance

- **The rule-lookup cache is bounded.** Every `(subject type, action)` pair
  asked about was remembered forever, and both halves can come from data — a
  subject type read out of a payload, an action out of a deep link. Past 512
  pairs the answer is recomputed instead, which is a merge of two sorted lists.
- **A field-narrowed lookup no longer copies when it filters nothing.** Any
  per-field rule in the set was enough to allocate a new list on every call,
  once per row of a list screen.
- Measured, in `benchmark/casl_benchmark.dart`. On an M-series laptop, over a
  thousand rules: `can` against a subject type **46 ns**, against an instance
  with conditions **133 ns**, for an administrator's `manage:all` **50 ns**;
  building the index **137 µs**; `unpackRules` of a thousand rules **54 µs**.

### Internal

- A **parity harness** (`tool/parity/`) runs 94 cases through a pinned
  `@casl/ability@7.0.1` and records its answers; `test/parity_test.dart`
  replays them. Every case either matches, is a recorded deviation with a
  stated reason, or is pending against a tracked finding — and a pending case
  asserts the divergence *still exists*, so fixing one fails the build until
  the marker is cleared. `melos run parity` regenerates and diffs it.

  It is why the "wire-compatible" claim in this package's documentation is
  checked rather than asserted, and it found a divergence the original audit
  had missed.

## 0.1.0

- Initial release: rules, abilities, the rule index and its precedence,
  action aliases, and the builder.
