# casl

Isomorphic authorisation for Dart, wire-compatible with
[CASL.js](https://casl.js.org) v7.

Your server already decides what a user may do. This lets a Dart client ask the
**same rules** the same question — so a button and an endpoint cannot disagree,
and nobody has to maintain the policy twice.

```dart
final ability = createMongoAbility([
  RawRule.of(action: 'read', subject: 'Article'),
  RawRule.of(
    action: 'update',
    subject: 'Article',
    conditions: {'authorId': currentUserId},
  ),
]);

ability.can('read', 'Article');     // may I read articles at all?
ability.can('update', article);     // may I update *this* one?
```

| | |
|---|---|
| **Wire-compatible, and checked** | 94 cases run through the real `@casl/ability@7.0.1` and replayed here, so a divergence fails a build rather than reaching a user |
| **Type-safe at no cost** | declare your actions and a typo stops compiling — and they are still plain strings on the wire |
| **Pure Dart, one dependency** | `meta`. Runs in Flutter, on a server, in a build script |
| **Fast** | `can` in ~50 ns against a subject type, ~130 ns against an instance, over a thousand rules |
| **Widgets** | [`casl_flutter`](https://pub.dev/packages/casl_flutter) |

---

## Contents

- [Install](#install)
- [The model in one minute](#the-model-in-one-minute)
- [Writing rules](#writing-rules)
- [Making a typo stop compiling](#making-a-typo-stop-compiling)
- [Three things that surprise people](#three-things-that-surprise-people)
- [Subject types, and why Dart needs care here](#subject-types-and-why-dart-needs-care-here)
- [Conditions](#conditions)
- [Field-level rules](#field-level-rules)
- [Turning rules into a database query](#turning-rules-into-a-database-query)
- [Taking rules from a server](#taking-rules-from-a-server)
- [Refusing, with a reason](#refusing-with-a-reason)
- [Action aliases](#action-aliases)
- [Reacting to a change of rules](#reacting-to-a-change-of-rules)
- [Extending it](#extending-it)
- [Testing](#testing)
- [Performance](#performance)
- [API reference](#api-reference)
- [Compared with CASL.js](#compared-with-casljs)
- [Porting from CASL.js](#porting-from-casljs)

---

## Install

```yaml
dependencies:
  casl: ^1.0.0
```

```dart
import 'package:casl/casl.dart';
```

Coming from 0.1.0? [`MIGRATING.md`](MIGRATING.md).

---

## The model in one minute

A **rule** grants (or forbids) an **action** on a **subject**, optionally
narrowed by **conditions** and **fields**.

```dart
RawRule.of(
  action: 'update',                       // what
  subject: 'Article',                     // to what kind of thing
  conditions: {'authorId': 7},            // only those matching
  fields: ['title', 'body'],              // only these parts of them
  inverted: false,                        // grant, or forbid
  reason: null,                           // shown when it forbids
);
```

An **ability** is an ordered list of rules that answers `can`.

The pieces, and where each is decided:

| Term | Is | Decided by |
|---|---|---|
| Action | a verb — `read`, `update`, `manage` | you |
| Subject type | a noun — `Article`, `all` | you |
| Subject | a subject type, **or** an instance of one | the call site |
| Condition | a MongoDB-shaped test over the instance | the rule |
| Field | one property of the subject | the call site |

Actions and subject types are strings on the wire, because the set is the
server's rather than the client's — a new subject type added on the backend
must not need an app release to be *checkable*, only to be *used*. They do not
have to be strings in your code; see
[making a typo stop compiling](#making-a-typo-stop-compiling).

---

## Writing rules

Rules usually arrive from a server. When you write them by hand, `defineAbility`
is the shortest way:

```dart
final ability = defineAbility((can, cannot) {
  can('read', 'Article');
  can.each(['update', 'delete'], 'Article', {'authorId': userId});
  cannot('delete', 'Article', {'published': true})
      .because('a published article cannot be deleted');
});
```

`can` and `cannot` are the same objects `AbilityBuilder` exposes, so name them
whatever reads best where you are — `allow` and `forbid` if `can` next to
`ability.can` confuses people. `can(…)` writes a rule about one action;
`can.each([…])` writes **one** rule covering several.

`AbilityBuilder` is the same thing spread out, for when the rules are assembled
across several branches:

```dart
final builder = AbilityBuilder()
  ..can('read', 'Article')
  ..can.each(['update', 'delete'], 'Article', {'authorId': userId});

if (user.isModerator) builder.can('publish', 'Article');

final moderatorAbility = builder.build();
```

Conditions and fields are positional, in that order —
`can(action, subject, conditions, fields)`. CASL.js overloads its third
parameter on the type it is given; Dart cannot, so the order is fixed and the
analyzer checks it. Conditions come first because they are far more common; a
rule with fields and no conditions passes `null` for them.

**Order is meaning.** Write the broad grant first and narrow it afterwards —
see below.

---

## Making a typo stop compiling

`ability.can('reed', article)` compiles. It denies. It denies forever, quietly,
and surfaces weeks later as a support ticket about a missing button. Nothing in
the type system, the tests or the analyzer catches it, because `'reed'` is a
perfectly good `String`.

Declare your vocabulary once and it does not compile:

```dart
extension type const AppAction(String wire) implements String {
  static const read = AppAction('read');
  static const create = AppAction('create');
  static const update = AppAction('update');
  static const delete = AppAction('delete');
  static const manage = AppAction('manage');

  /// For a screen that lists them. Extension types have no `values` of their
  /// own — and unlike an enum's, this one costs nothing at runtime.
  static const values = <AppAction>[read, create, update, delete, manage];
}

extension type const AppSubject(String wire) implements String {
  static const article = AppSubject('Article');
  static const user = AppSubject('User');
  static const all = AppSubject('all');
}

typedef AppAbility = Ability<AppAction, AppSubject>;
```

<!-- continues -->

```dart
final AppAbility typed = defineAbility<AppAction, AppSubject>((can, cannot) {
  can(AppAction.read, AppSubject.article);
  can(AppAction.update, AppSubject.article, {'authorId': userId});
});

typed.can(AppAction.update, article);
```

<!-- continues -->

```dart
final wrong = createMongoAbility<AppAction, AppSubject>(const []);

wrong.can('reed', article);      // ✗ does not compile
```

**This costs nothing.** Extension types erase completely: an `AppAction` *is* a
`String` at runtime. Not one byte changes on the wire, there is no conversion
per check, and rules from a server need no adaptation — including rules
mentioning actions your vocabulary has never heard of, which still index and
still deny.

Leaving the type arguments off gives `Ability<String, String>`, which is exactly
what it always was. Typed and untyped code interoperate:
`Ability<AppAction, AppSubject>` *is* an `Ability<String, String>`, so anything
written against the untyped form keeps working.

Two things it does not catch, and they are the same two TypeScript does not
catch either: a typo inside the declaration
(`static const read = AppAction('reed')`), and anything reached through
`dynamic`.

---

## Three things that surprise people

### 1. The last matching rule wins

Not "cannot beats can".

<!-- fragment: a cascade shown without its builder, to keep the two lines adjacent -->

```dart
..cannot('read', 'Article')
..can('read', 'Article')      // → can('read', 'Article') is TRUE
```

Rules are prioritised in reverse, and `can` returns the first match that is
not inverted. So a rule written later overrides one written earlier, in either
direction.

This is what makes rule sets **composable** — a role can be layered on top of a
base grant and actually change it:

```dart
final layered = defineAbility((can, cannot) {
  can('manage', 'all');                            // base: an administrator
  cannot('delete', 'Invoice');                     // except: finance keeps them
  can('delete', 'Invoice', {'status': 'draft'});   // unless it is a draft
});
```

It is also CASL.js's behaviour exactly. A library implementing "any matching
`cannot` forbids" would answer differently from your server, on precisely the
accounts whose rules are interesting.

### 2. `manage` and `all` are not special-cased

They are ordinary entries in the rule index that every lookup merges with. One
rule, `manage:all`, is an administrator's entire grant:

```dart
final everything = createMongoAbility([
  RawRule.of(action: 'manage', subject: 'all'),
]);

everything.can('destroy', 'Invoice');   // true
```

Which is why a permission check written as
`permissions.contains('read:User')` locks out precisely the account allowed to
do everything, and nobody else — a bug that survives testing, because the
developer testing it is usually the administrator.

Both names are configurable, because they are conventions rather than laws:

```dart
Ability(const [], anyActionName: 'ALL', anySubjectTypeName: 'EVERYTHING');
```

### 3. Asking about a type is a different question from asking about an instance

```dart
ability.can('update', 'Article');   // is there ANY article I may update?
ability.can('update', article);     // may I update this one?
```

With no instance there is nothing to evaluate conditions against. A
**permitting** rule therefore answers **yes** — there may well be an article
you can edit, so do not hide the menu item — while a **forbidding** rule
answers **no** only if its conditions restrict nothing.

Without that asymmetry, "you cannot edit articles you did not write" would read
as "you cannot edit articles", and the feature would disappear for everyone.

Use the type form for navigation and menus, the instance form for the control
attached to a particular row.

---

## Subject types, and why Dart needs care here

CASL.js reads `object.constructor.name`. The Dart equivalent is
`runtimeType.toString()` — and **`--obfuscate` renames it**. A direct
translation would authorise correctly in debug and silently differently in the
build that ships, with nothing in the logs either way.

So declare the name. On a class you own:

```dart
class Article with CaslSubject {
  @override
  String get caslSubjectType => 'Article';
}
```

<!-- continues -->

```dart
ability.can('update', Article());
```

At the call site, for anything else — a JSON map, a generated model, a type
from another package:

```dart
ability.can('update', subject('Article', json));
```

Or supply your own detection for a whole application. Returning null defers to
the default, so `subject()` and `CaslSubject` keep working underneath it:

```dart
class ApiModel {
  ApiModel(this.type);
  final String type;
}

final detected = createMongoAbility(
  const [],
  detectSubjectType: (value) => value is ApiModel ? value.type : null,
);
```

`runtimeType` remains the last resort, and is documented as one.

---

## Conditions

MongoDB-shaped, and the same fourteen operators CASL.js ships with:

`$eq` `$ne` `$lt` `$lte` `$gt` `$gte` `$in` `$nin` `$all` `$size` `$regex`
`$options` `$elemMatch` `$exists`

```dart
final scoped = defineAbility((can, _) {
  can('read', 'Article', {
    'authorId': userId,
    'status': {r'$in': ['draft', 'review']},
    'views': {r'$gte': 100},
    'title': {r'$regex': '^draft', r'$options': 'i'},
  });
});
```

Several keys are an implicit AND. Several operators on one field are an AND
too, so `{'views': {r'$gte': 10, r'$lte': 50}}` is a range.

Nested paths use dots, and a list part-way along is flattened — so
`'comments.author'` over a list of comments reads as a list of authors, and the
condition matches if *any* of them does. That is MongoDB's behaviour and the
reason the dotted form does the useful thing.

### There are no top-level operators

No `$or`, no `$and`, no `$nor`. A query is an implicit AND of field tests,
which is CASL's default exactly. An unknown operator **throws** rather than
being ignored — ignoring one turns a restrictive rule into a permissive one.

If your server sends them, switch them on rather than refusing them:

```dart
final withLogical = createMongoAbility(
  const [],
  parser: const MongoQueryParser().withOperators(logicalOperators),
);
```

### The parts worth reading twice

<!-- fragment: a table of condition syntax against the values each matches -->

```dart
// a list matches if it CONTAINS the value
{'tags': 'draft'}                  // matches {'tags': ['draft', 'new']}

// or if the whole list is equal
{'tags': ['a', 'b']}               // matches {'tags': ['a', 'b']} exactly

// null means absent OR null — of something that could have had the field
{'deletedAt': null}                // matches {} and {'deletedAt': null}
{'deletedAt': {r'$exists': false}} // absent only
{'deletedAt': {r'$exists': true}}  // present, even if null
```

Reading a model directly, with no conversion to a map on every check:

```dart
class Invoice with CaslSubject, CaslRecord {
  Invoice(this.total);
  final int total;

  @override
  String get caslSubjectType => 'Invoice';

  @override
  Object? caslField(String name) => switch (name) {
    'total' => total,
    _ => null,
  };
}
```

Or supply a reader for a shape you do not control:

```dart
final rows = createMongoAbility(
  const [],
  read: (target, field) => (target as Map<String, Object?>)[field],
);
```

---

## Field-level rules

A rule may name the fields it covers. `*` stops at a dot and `**` crosses them,
as in a shell glob:

```dart
final form = defineAbility((can, cannot) {
  can('update', 'Article', null, ['title', 'body', 'address.**']);
  cannot('update', 'Article', {'published': true}, ['title']);
});

form.can('update', 'Article', 'title');
```

Asking "which fields, then?" is what a form needs — and asking rule by rule
would get it wrong, because a later rule can take a field back:

```dart
final editable = permittedFieldsOf(
  ability,
  'update',
  article,
  allFields: const ['title', 'body', 'published'],
);
```

`allFields` cannot be inferred: a rule with no `fields` means *every* field, and
only you know what a subject's fields are. Dart has no runtime reflection to
fall back on, and generating the list would tie it to your class's identifiers
rather than to the names the server writes rules about.

For a repository asking per row, hold the parts that do not change:

```dart
final readable = AccessibleFields(
  ability,
  'read',
  allFieldsOf: (type) => const {
    'Article': ['title', 'body'],
    'User': ['name', 'email'],
  }[type]!,
);

readable.ofType('Article');   // every article's readable fields
readable.of(article);         // this one's, conditions evaluated
```

---

## Turning rules into a database query

`can` answers about one record. A list screen needs the other question — *which
records* — and asking `can` per row means fetching rows the user may not see
and throwing them away. That is wrong on a page of ten and impossible on a
table of ten million.

```dart
List<Object?> readableArticles() {
  final where = rulesToAst(ability, 'read', 'Article');

  if (where == null) return const [];     // nothing at all is permitted
  return database.select(where);
}
```

`null` means "fetch nothing" and is **not** the same as an empty filter, which
means "fetch everything". Conflating them is the bug this function exists to
prevent.

The result is a `Condition` tree — a sealed type you pattern-match to produce
whatever your database speaks:

```dart
String toSql(Condition condition) => switch (condition) {
  FieldCondition(:final operator, :final field, :final value) =>
    '$field $operator $value',
  CompoundCondition(:final operator, :final conditions) =>
    '(${conditions.map(toSql).join(' $operator ')})',
};
```

`rulesToCondition` is the same algorithm over any target language, if you would
rather build a Drift `Expression` than walk a tree.

It is not simply "OR the permitting rules together". `can` stops at the first
matching rule, so a permitting rule is only reached when no higher-priority
forbidding rule caught the record first — and a query has no such ordering.
Each permitting rule becomes its own OR branch, bounded by the negation of
every forbidding rule above it:

<!-- fragment: rules and the query they produce, side by side -->

```dart
..can('read', 'Article', {'published': true})     // lowest priority
..cannot('read', 'Article', {'secret': true})
..can('read', 'Article', {'pinned': true})        // highest

// → or(pinned, and(published, not(secret)))
```

---

## Taking rules from a server

`packRules` and `unpackRules` read and write CASL.js's compact array format —
the one meant for a JWT:

```dart
final compact = packRules(ability.rules);
final restored = unpackRules(compact);
```

`RawRule.fromJson` and `toJson` handle the verbose object form. Everything that
can go wrong reading a rule raises a **`FormatException`**, including a
condition your build cannot parse — so one catch clause covers the boundary:

```dart
void applyRules(List<Object?> incoming) {
  try {
    ability
      ..update(unpackRules(incoming))
      ..validateRules();
  } on FormatException catch (error) {
    log.warning('the server sent rules this build cannot read', error);
  }
}
```

`validateRules` is worth the line. Conditions compile **lazily**, and more
lazily than it looks — a rule checked only against a subject *type* never
compiles its conditions at all — so a rule carrying an operator this build does
not know can pass `can('read', 'Article')` and only throw later, when somebody
opens a list. `validateRules` moves that to a point you chose.

The other half of the answer, for a client that may be older than its server:

```dart
final tolerant = createMongoAbility(
  const [],
  onUnparsableCondition: UnparsableCondition.deny,
);
```

A rule it cannot read then grants nothing, instead of throwing. Denying rather
than ignoring is deliberate: a condition nobody can evaluate must not be read as
"no condition".

---

## Refusing, with a reason

Screens ask `can` and draw accordingly. The layer underneath — a use case
invoked from somewhere that should already have checked — wants to throw:

```dart
ability.throwUnlessCan('delete', article);
// ForbiddenError: published articles are kept
```

For a message the rule could not know:

```dart
ForbiddenError.from(ability)
    .setMessage('You cannot delete posts')
    .throwUnlessCan('delete', article);
```

And to report rather than raise — a disabled button that explains itself:

```dart
final refusal = ability.errorUnlessCan('delete', article);
final tooltip = refusal?.reason;   // the rule's own words, or null
```

`reason` is what the rule said. `message` is that, or the default if it said
nothing. Set the default once at startup — it is called at throw time, so
reading the current locale inside it works:

```dart
ForbiddenError.setDefaultMessage('Not authorised');
ForbiddenError.describe = (e) => 'You cannot ${e.action} a ${e.subjectType}';
```

---

## Action aliases

```dart
final resolve = createAliasResolver({
  'modify': ['update', 'delete'],
  'access': ['read', 'modify'],     // aliases may chain
});

final aliased = createMongoAbility(const [], resolveActions: resolve);
```

Aliases work in one direction only: granting `modify` grants `update` and
`delete`, but granting both does not grant `modify`. They are resolved once,
when the ability is built, which is what keeps `can` fast.

Cycles and aliases of `manage` are rejected — including indirect cycles, which
CASL.js documents itself as *not* detecting.

---

## Reacting to a change of rules

An ability is mutable. `update` replaces the whole grant, which is what a token
refresh does when a role has changed:

```dart
final off = ability.on('updated', (event) {});
ability.update(const []);
off();   // stop listening
```

`update` fires before the change and `updated` after. A UI wants the second; a
cache that needs to read the outgoing state wants the first. A listener may
unsubscribe — itself or another — from inside the callback.

In Flutter, [`casl_flutter`](https://pub.dev/packages/casl_flutter) does this
wiring for you.

---

## Extending it

Every part of the evaluation is a table you can add to. An operator takes two
halves — parsing `$name` into a condition, and evaluating that condition:

```dart
Condition parseMod(OperatorCall call) {
  final value = call.value;
  return value is List && value.length == 2
      ? FieldCondition('mod', call.field, value)
      : call.refuse('expects a list of two whole numbers');
}

bool interpretMod(
  FieldCondition node,
  Object? subject,
  ConditionInterpreter it,
) {
  final [divisor as int, remainder as int] = node.value! as List;
  return it.anyOf(
    it.valueOf(node, subject),
    (v) => v is int && v % divisor == remainder,
  );
}
```

<!-- continues -->

```dart
final extended = createMongoAbility(
  const [],
  parser: const MongoQueryParser().withOperators({r'$mod': parseMod}),
  interpreter: const ConditionInterpreter().withOperators(
    fields: {'mod': interpretMod},
  ),
);
```

Use `call.refuse` rather than throwing, so a client configured to tolerate rules
it cannot read still does. Think first about whether the server sending these
rules understands the same operator — a condition one side evaluates
differently is worse than one neither does.

The other seams: `read` for how a field is read from an object, `fieldsMatcher`
for the wildcard syntax, `equals` for how two values are compared, and
`conditionsMatcher` for replacing MongoDB syntax entirely. A rule's conditions
stay a `Map` so they can travel; a matcher may read that map however it likes,
including as the name of a Dart predicate.

---

## Testing

Test the function that *distributes* rules, not `can`:

```dart
List<RawRule> rulesFor({required bool isModerator}) =>
    defineAbility((can, cannot) {
      can('read', 'Article');
      if (isModerator) can('publish', 'Article');
    }).rules;
```

`can` is pure — for the same rules it always answers the same thing, and
testing it tests this package. What is worth testing is that a moderator gets
the moderator rules, because that is the part your application wrote.

---

## Performance

Over a thousand rules, on an M-series laptop
(`dart run benchmark/casl_benchmark.dart`):

| | |
|---|---|
| `can` against a subject type | 46 ns |
| `can` against an instance, conditions evaluated | 133 ns |
| `can` for an administrator — `manage:all` | 50 ns |
| `can` with a field, on a rule set that has per-field rules | 97 ns |
| Build the index | 137 µs |
| `unpackRules` of 1 000 rules | 54 µs |

---

## API reference

| | |
|---|---|
| **Defining** | `defineAbility` · `defineAbilityAsync` · `AbilityBuilder` · `RuleAdder` · `RuleRef` |
| **Asking** | `Ability.can` · `.cannot` · `.relevantRuleFor` · `.rulesFor` · `.possibleRulesFor` · `.actionsFor` |
| **Rules** | `RawRule` · `RawRule.of` · `RawRule.fromJson` · `Rule` · `RuleIndex` · `.update` · `.validateRules` |
| **Subjects** | `subject` · `ForcedSubject` · `CaslSubject` · `CaslRecord` · `detectSubjectTypeByRuntimeType` |
| **Conditions** | `createMongoAbility` · `MongoQueryParser` · `ConditionInterpreter` · `Condition` · `FieldCondition` · `CompoundCondition` · `CaslFields` |
| **Fields** | `permittedFieldsOf` · `AccessibleFields` · `fieldPatternMatcher` |
| **Queries** | `rulesToAst` · `rulesToCondition` · `rulesToFields` · `QueryLanguage` |
| **Interop** | `packRules` · `unpackRules` · `ForbiddenError` · `AbilityGuard` |
| **Extending** | `logicalOperators` · `defaultOperators` · `UnparsableCondition` · `ConditionFormatException` · `ValueEquality` · `caslStrictJsEquality` |

Every exported member is documented; `dart doc` is the reference.

---

## Compared with CASL.js

Parity is **tested, not claimed**. Ninety-four cases run through a pinned
`@casl/ability@7.0.1` and are replayed here, so a divergence fails a build
rather than reaching a user:

```bash
cd tool/parity && npm run generate   # records what CASL.js answers
cd packages/casl && dart test        # replays it
```

Everything matches — precedence, the fourteen operators, the packed wire
format, `rulesToCondition` — except the differences below. Each is deliberate,
each is pinned by a fixture carrying its reason, and none can be introduced by
accident.

### Behaviour

| | Here | CASL.js | Why |
|---|---|---|---|
| `{'tags': ['a','b']}` against `{'tags': ['a','b']}` | matches | does not | CASL.js compares with `===`, so it cannot match a nested object or a whole array by value. We compare by value, as MongoDB does. Pass `strictJsEquality: true` to get their behaviour exactly |
| `{'x': {r'$gt': 3}}` against `{'x': '10'}` | denies | permits | JavaScript coerces across types. A condition comparing a string to a number is a mistake, and denying is the safe reading of a mistake |
| An unknown operator (`$or`, `$mod`) | throws | silently never matches | A rule nobody can evaluate is a rule nobody should trust. `UnparsableCondition.deny` and `validateRules` are the two levers |
| `permittedFieldsOf` with `['address.*']` | `['address.city']` | `['address.*']` | A form needs field names, not patterns. Order follows `allFields`, because a form's field order is a design decision |

### Shape

| | Here | CASL.js | Why |
|---|---|---|---|
| Subject types | declared (`CaslSubject` / `subject()`) | read from `constructor.name` | `runtimeType` is wrong under `--obfuscate`, silently, in release builds only |
| Field matcher | defaulted | must be supplied | `*` and `**` mean one thing everywhere; defaulting cannot change what a rule means |
| Packing a rule with no subject | `["read","all"]` | `["read"]` | Both unpack to the same ability and index identically. Remembering whether the subject was written down would be state carried for a cosmetic difference |
| Reading a bad rule | always a `FormatException` | mixed | An `Error` means "a programmer wrote this wrong", and there is no programmer involved in a payload off a network |

Naming follows v7: what v6 called `PureAbility` is `Ability` here, and the old
`Ability` that bundled a Mongo matcher is `createMongoAbility`.

---

## Porting from CASL.js

| `@casl/ability` | `casl` | |
|---|---|---|
| `new Ability(rules, opts)` | `Ability(rules, …)` | |
| `createMongoAbility(rules)` | `createMongoAbility(rules)` | |
| `new AbilityBuilder(createMongoAbility)` | `AbilityBuilder()` | the factory defaults |
| `defineAbility((can, cannot) => …)` | `defineAbility((can, cannot) { … })` | plus `defineAbilityAsync` |
| `can(['a','b'], 'S', conds)` | `can.each(['a','b'], 'S', conds)` | Dart cannot overload on argument type |
| `can('a', 'S', ['f'], conds)` | `can('a', 'S', conds, ['f'])` | conditions before fields — the common case first |
| `.because(reason)` | `.because(reason)` | chainable, as there |
| `ability.can(a, s, f)` | `ability.can(a, s, f)` | |
| `ability.update(rules)` | `ability.update(rules)` | returns the ability, as there |
| `ability.on('updated', fn)` | `ability.on('updated', fn)` | returns an `Unsubscribe` |
| `subject('Article', obj)` | `subject('Article', obj)` | |
| `ForbiddenError.from(a).setMessage(m).throwUnlessCan(…)` | same | plus `a.throwUnlessCan(…)` |
| `ForbiddenError.setDefaultMessage(str)` | same | a function goes to `ForbiddenError.describe` |
| `createAliasResolver(map)` | `createAliasResolver(map)` | passed as `resolveActions:` |
| `buildMongoQueryMatcher(instr, interp)` | `MongoQueryParser.withOperators` + `ConditionInterpreter.withOperators` | both halves, explicitly |
| `packRules` / `unpackRules` | same | |
| `permittedFieldsOf(a, act, sub, {fieldsFrom})` | `permittedFieldsOf(a, act, sub, allFields:)` | patterns expanded for you |
| `AccessibleFields` | `AccessibleFields` | |
| `rulesToFields` / `rulesToAST` / `rulesToQuery` | `rulesToFields` / `rulesToAst` / `rulesToCondition` | |
| `MongoAbility<[Action, Subject]>` | `Ability<AppAction, AppSubject>` | extension types over `String` |
| `hkt`, `Generics`, `InferSubjects` | — | type-level only; the generics above solve what they solve |
| class as a subject type, `modelName` | — | `runtimeType` is unsafe under obfuscation; declare the name instead |

---

## Licence

MIT.
