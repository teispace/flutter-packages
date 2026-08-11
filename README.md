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
| **Wire-compatible** | `unpackRules(json)` reads exactly what `@casl/ability`'s `packRules` writes |
| **Pure Dart, one dependency** | `meta`. Runs in Flutter, on a server, in a build script |
| **Complete** | conditions, field-level rules, aliases, events, query building |
| **Widgets** | [`casl_flutter`](https://pub.dev/packages/casl_flutter) |

---

## Contents

- [Install](#install)
- [The model in one minute](#the-model-in-one-minute)
- [Writing rules](#writing-rules)
- [Three things that surprise people](#three-things-that-surprise-people)
- [Subject types, and why Dart needs care here](#subject-types-and-why-dart-needs-care-here)
- [Conditions](#conditions)
- [Field-level rules](#field-level-rules)
- [Turning rules into a database query](#turning-rules-into-a-database-query)
- [Sharing rules with a CASL.js server](#sharing-rules-with-a-casljs-server)
- [Refusing, with a reason](#refusing-with-a-reason)
- [Action aliases](#action-aliases)
- [Reacting to a change of rules](#reacting-to-a-change-of-rules)
- [Custom condition languages](#custom-condition-languages)
- [Testing](#testing)
- [API reference](#api-reference)
- [Compared with CASL.js](#compared-with-casljs)

---

## Install

```yaml
dependencies:
  casl: ^0.1.0
```

```dart
import 'package:casl/casl.dart';
```

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

Nothing here is an enum. Actions and subject types are strings because the set
is the server's, not the client's — a new subject type added on the backend
must not require an app release to be *checkable*, only to be *used*.

---

## Writing rules

Rules usually arrive from a server. When you write them by hand,
`AbilityBuilder` reads better than a list of `RawRule`s:

```dart
final builder = AbilityBuilder()
  ..can('read', 'Article')
  ..can(['update', 'delete'], 'Article', {'authorId': userId})
  ..cannot('delete', 'Article', {'published': true});

builder
    .cannot('delete', 'Article', {'locked': true})
    .because('a locked article cannot be deleted');

final ability = builder.build(create: createMongoAbility);
```

Every field takes one value or a list: `'read'` or `['read', 'update']`.

**Order is meaning.** Write the broad grant first and narrow it afterwards —
see below.

---

## Three things that surprise people

### 1. The last matching rule wins

Not "cannot beats can".

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
..can('manage', 'all')            // base: an administrator
..cannot('delete', 'Invoice')     // except: finance keeps invoices
..can('delete', 'Invoice', {'status': 'draft'})   // unless it is a draft
```

It is also CASL.js's behaviour exactly. A library implementing "any matching
`cannot` forbids" would answer differently from your server, on precisely the
accounts whose rules are interesting.

### 2. `manage` and `all` are not special-cased

They are ordinary entries in the rule index that every lookup merges with. One
rule, `manage:all`, is an administrator's entire grant:

```dart
final admin = createMongoAbility([RawRule.of(action: 'manage', subject: 'all')]);
admin.can('destroy', 'Invoice');   // true
```

Which is why a permission check written as
`permissions.contains('read:User')` locks out precisely the account allowed to
do everything, and nobody else — a bug that survives testing, because the
developer testing it is usually the administrator.

Both names are configurable, because they are conventions rather than laws:

```dart
Ability(rules, anyActionName: 'ALL', anySubjectTypeName: 'EVERYTHING');
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

ability.can('update', article);
```

At the call site, for anything else — a JSON map, a generated model, a type
from another package:

```dart
ability.can('update', subject('Article', json));
```

Or supply your own detection for a whole application:

```dart
createMongoAbility(rules, detectSubjectType: (value) => switch (value) {
  ApiModel(:final type) => type,
  _ => null,   // fall through to the default
});
```

`runtimeType` remains the last resort, and is documented as one.

---

## Conditions

MongoDB-shaped, and the same operators CASL.js ships with:

`$eq` `$ne` `$lt` `$lte` `$gt` `$gte` `$in` `$nin` `$all` `$size` `$regex`
`$options` `$elemMatch` `$exists`

```dart
conditions: {
  'authorId': userId,
  'status': {r'$in': ['draft', 'review']},
  'views': {r'$gte': 100},
  'title': {r'$regex': '^draft', r'$options': 'i'},
}
```

### There are no top-level operators

No `$or`, no `$and`, no `$nor`. A query is an implicit AND of field tests,
which is CASL's default exactly. An unsupported operator **throws** rather than
being ignored — ignoring one turns a restrictive rule into a permissive one.

If your server really does send more, add them:

```dart
final parser = const MongoQueryParser().withOperators({
  r'$or': (call) => CompoundCondition('or', [
    for (final query in call.value! as List<Object?>)
      call.parser.parse(query! as Map<String, Object?>),
  ]),
});

createMongoAbility(rules, parser: parser);
```

### Lists behave as they do in MongoDB

This is the part worth reading twice:

```dart
// a list matches if it CONTAINS the value
{'tags': 'draft'}                  // matches {'tags': ['draft', 'new']}

// or if the whole list is equal
{'tags': ['a', 'b']}               // matches {'tags': ['a', 'b']} exactly

// a comparison is satisfied by any one element
{'scores': {r'$gte': 80}}          // matches {'scores': [10, 90]}

// a list part-way along a path is flattened, not indexed
{'comments.author': 'ada'}         // is ANY comment Ada's?

// unless the segment is numeric
{'comments.0.author': 'ada'}       // is the FIRST comment Ada's?
```

### `null` and `$exists` ask different things

```dart
{'deletedAt': null}                // absent OR null
{'deletedAt': {r'$exists': false}} // absent
{'deletedAt': {r'$exists': true}}  // present, even if null
```

Both are questions about the *parent* rather than the value. Getting the pair
wrong makes optional fields behave inconsistently, in ways nobody traces back
to authorisation.

### Matching your own models

Conditions read from a `Map` out of the box. To match a model directly, add
`CaslRecord`:

```dart
class Article with CaslSubject, CaslRecord {
  Article({required this.authorId, required this.status});

  final int authorId;
  final String status;

  @override
  String get caslSubjectType => 'Article';

  @override
  Object? caslField(String name) => switch (name) {
    'authorId' => authorId,
    'status' => status,
    _ => null,
  };
}
```

The switch is written by hand on purpose. Generating it would tie the field
names to your Dart identifiers, and the server's names are allowed to differ —
which is exactly when a generated mapping quietly stops matching.

For a shape neither `Map` nor `CaslRecord` covers, supply a reader:

```dart
createMongoAbility(rules, read: (target, field) => (target as Row)[field]);
```

---

## Field-level rules

```dart
RawRule.of(action: 'update', subject: 'Article', fields: ['title', 'body']);

ability.can('update', article, 'title');    // true
ability.can('update', article, 'salary');   // false
ability.can('update', article);             // true — "any field at all?"
```

Patterns work like shell globs — `*` inside one segment, `**` across them:

| Pattern | Matches | Does not match |
|---|---|---|
| `title` | `title` | `titles` |
| `address.*` | `address`, `address.city` | `address.geo.lat` |
| `address.**` | `address`, `address.city`, `address.geo.lat` | `title` |
| `*` | `title` | `address.city` |
| `**` | anything | — |

Note that `address.*` matches `address` itself: a rule about the parts of a
thing is taken to be a rule about the thing.

### For a form, ask for the list

The answers do not compose — a later rule can take a field back — so asking
per field gives the right answer per field and the wrong list:

```dart
permittedFieldsOf(
  ability,
  'update',
  article,
  allFields: ['title', 'body', 'published', 'authorId'],
);   // → ['title', 'body']
```

`allFields` is required and cannot be inferred: a rule with no `fields` means
*every* field, and Dart has no runtime reflection to enumerate them. Patterns
are resolved against the names you pass, and the result keeps **your** order,
because field order in a form is a design decision.

### Prefilling from conditions

```dart
rulesToFields(ability, 'create', 'Article');   // → {'status': 'draft'}
```

So a user who may only create drafts gets a form that already says draft,
rather than one that lets them choose and then refuses. Operator queries are
skipped — `{$gte: 100}` is a range, and inventing a value from it would present
a guess to the user as a fact.

---

## Turning rules into a database query

`can` answers about one record. A list screen needs the other question: *which
records may this user see?* Asking `can` per row means fetching rows the user
may not see and discarding them — wrong on a page of ten, impossible on a table
of ten million.

```dart
final where = rulesToAst(ability, 'read', 'Article');

if (where == null) return const [];     // nothing at all is permitted
return database.select(translate(where));
```

**`null` is not an empty filter.** Null means fetch nothing; an unrestricted
result means fetch everything. Conflating them is the difference between an
empty list and the entire table.

### Building for your own query language

`rulesToCondition` is the same algorithm over any language with an *and*, an
*or* and a negation:

```dart
final sql = rulesToCondition<String>(
  ability.rulesFor('read', 'Article'),
  (rule) => rule.conditions!.entries.map((e) => '${e.key} = ?').join(' AND '),
  QueryLanguage(
    and: (parts) => parts.length == 1 ? parts.single : '(${parts.join(' AND ')})',
    or: (parts) => parts.length == 1 ? parts.single : '(${parts.join(' OR ')})',
    not: (part) => 'NOT ($part)',
    unrestricted: () => '1 = 1',
  ),
);
```

### Why it is not "OR the permitting rules together"

`can` walks rules in priority order and stops at the first match, so a
permitting rule is only reached when no higher-priority forbidding rule caught
the record first. A query has no such ordering — it is one boolean expression —
so the sequence has to be flattened.

Each permitting rule becomes a branch of an OR, bounded by the negation of
every forbidding rule **above** it. Rules below it are ignored, because
reaching it already means they did not apply.

```dart
..can('read', 'Article', {'published': true})     // lowest priority
..cannot('read', 'Article', {'secret': true})
..can('read', 'Article', {'pinned': true})        // highest

// → or(pinned, and(published, not(secret)))
```

`pinned` is unbounded because the forbidding rule sits *below* it. This is
subtle enough that the package tests it two ways: against an expected tree, and
by checking the query and `can()` agree record by record.

---

## Sharing rules with a CASL.js server

```ts
// server
res.json({ rules: packRules(ability.rules) });
```

```dart
// client
final rules = unpackRules(json['rules'] as List<Object?>);
final ability = createMongoAbility(rules);
```

The packed form is one array per rule with the empty tail dropped, so the
common rule costs two strings rather than six keys and their names:

```json
[["manage","all"],
 ["read,update","Article",{"authorId":7}],
 ["delete","Article",0,1,0,"published articles are kept"]]
```

Slots are positional — action, subject, conditions, inverted, fields, reason —
so a rule with fields and no conditions still carries the `0` that holds the
place. Plain JSON works too, via `RawRule.fromJson` / `toJson`, at the cost of
a larger payload.

`packSubject` / `unpackSubject` translate subject type names in flight, for a
server whose rules name classes rather than strings.

---

## Refusing, with a reason

For the layer beneath the UI, where being asked to do something forbidden means
a bug or a stale screen rather than an expected answer:

```dart
ability.throwUnlessCan('delete', article);
await repository.delete(article.id);
// ForbiddenError: published articles are kept
```

The message prefers the forbidding rule's own `reason` — the difference between
"you cannot do that" and something the user can act on. `errorUnlessCan`
returns it instead of throwing, for putting the reason beside a disabled
control:

```dart
final refusal = ability.errorUnlessCan('delete', article);
Tooltip(message: refusal?.message ?? '', child: ...);
```

Translate the fallback once, at startup:

```dart
ForbiddenError.describe = (e) => t.errors.notAllowed(action: e.action);
```

---

## Action aliases

```dart
final resolve = createAliasResolver({
  'modify': ['update', 'delete'],
  'access': ['read', 'modify'],     // aliases may chain
});

final ability = createMongoAbility(rules, resolveActions: resolve);
// can('access', 'Article') now grants a 'delete' check
```

Cycles and aliasing the wildcard action are refused at construction. Both
mistakes produce an ability that is *wrong* rather than one that fails, and
neither is visible in a test that happens not to use the alias.

---

## Reacting to a change of rules

An ability is mutable — a role change replaces the grant in place:

```dart
final off = ability.on('updated', (_) => rebuild());
ability.update(unpackRules(response['rules'] as List<Object?>));
off();   // stop listening
```

`update` fires before the change, with the old rules still in force, and
`updated` after. A UI wants the second; a cache that has to read the outgoing
grant wants the first. `casl_flutter` does this for you.

---

## Custom condition languages

`Ability` understands no condition language of its own. `createMongoAbility`
supplies the MongoDB one; anything else is a `ConditionsMatcher`:

```dart
Ability(rules, conditionsMatcher: (conditions) => MyMatch(conditions));
```

A rule with conditions and no matcher **throws when it is compiled**, rather
than silently matching nothing — a permission system that denies for reasons
nobody can find is worse than one that fails.

Implement `ParsedConditions` as well as `ConditionsMatch` if you want
`rulesToAst` to work with your language.

---

## Testing

Everything is a plain value, so there is nothing to mock:

```dart
test('an author may edit their own article', () {
  final ability = createMongoAbility([
    RawRule.of(
      action: 'update',
      subject: 'Article',
      conditions: {'authorId': 7},
    ),
  ]);

  expect(ability.can('update', subject('Article', {'authorId': 7})), isTrue);
  expect(ability.can('update', subject('Article', {'authorId': 8})), isFalse);
});
```

The most valuable test to write against your own rules is the round trip: take
a payload your server actually produced, unpack it, and assert on the answers.
That is the one that catches the two sides drifting apart.

---

## API reference

**Building**
`RawRule` · `RawRule.of` · `RawRule.fromJson` · `AbilityBuilder` · `Ability` ·
`createMongoAbility`

**Asking**
`can` · `cannot` · `relevantRuleFor` · `rulesFor` · `possibleRulesFor` ·
`actionsFor` · `detectSubjectType`

**Subjects**
`CaslSubject` · `subject()` · `CaslRecord` · `DetectSubjectType` ·
`FieldReader`

**Conditions**
`MongoQueryParser` · `OperatorCall` · `Condition` · `FieldCondition` ·
`CompoundCondition` · `ConditionInterpreter` · `mongoConditionsMatcher`

**Fields**
`fieldPatternMatcher` · `permittedFieldsOf` · `rulesToFields`

**Queries**
`rulesToAst` · `rulesToCondition` · `QueryLanguage`

**Interop**
`packRules` · `unpackRules` · `PackedRule`

**Errors**
`ForbiddenError` · `throwUnlessCan` · `errorUnlessCan`

**Changes**
`update` · `on('update' | 'updated')` · `AbilityUpdate`

**Aliases**
`createAliasResolver`

---

## Compared with CASL.js

Everything above matches `@casl/ability` v7, including the packed wire format
and the precedence rules. Two deliberate differences, neither of which can
change what a rule means:

| | Here | CASL.js |
|---|---|---|
| Subject types | declared (`CaslSubject` / `subject()`) | read from `constructor.name` |
| Field matcher | defaulted | must be supplied |

The first exists because Dart obfuscation makes the JS approach unsafe. The
second replaces a throw with the answer everyone was going to supply.

Naming follows v7: what v6 called `PureAbility` is `Ability` here, and the old
`Ability` that bundled a Mongo matcher is `createMongoAbility`.

Not ported: the TypeScript type-level machinery (`hkt`, `Generics`,
`InferSubjects`), which has no Dart equivalent and no runtime behaviour, and
the ORM integrations (`@casl/mongoose`, `@casl/prisma`) — `rulesToCondition` is
the hook those are built on, and it is here.

---

## Licence

MIT.
