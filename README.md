# casl

Isomorphic authorisation for Dart, wire-compatible with
[CASL.js](https://casl.js.org).

Your server already decides what a user may do. This lets the client ask the
**same rules** the same question, so a button and an endpoint cannot disagree.

```dart
final ability = createMongoAbility([
  RawRule.of(action: 'read', subject: 'Article'),
  RawRule.of(
    action: 'update',
    subject: 'Article',
    conditions: {'authorId': currentUserId},
  ),
]);

ability.can('read', 'Article');     // true  — may I read articles at all?
ability.can('update', article);     // true  — may I update *this* one?
```

- **Zero configuration to share rules.** `unpackRules(json)` reads exactly what
  `@casl/ability`'s `packRules` writes.
- **One dependency** (`meta`), pure Dart. Runs in Flutter, on a server, in a
  build script.
- **Widgets** live in [`casl_flutter`](https://pub.dev/packages/casl_flutter).

---

## Install

```yaml
dependencies:
  casl: ^0.1.0
```

## Writing rules by hand

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

**Order is meaning.** Write the broad grant first and narrow it afterwards.

---

## Three things that surprise people

### 1. The last matching rule wins

Not "cannot beats can".

```dart
..cannot('read', 'Article')
..can('read', 'Article')      // → can('read', 'Article') is TRUE
```

This is what makes rule sets composable: a role can be layered on top of a base
grant and actually override it, in either direction. It is also CASL.js's
behaviour exactly — a library that implemented "any matching `cannot` forbids"
would answer differently from your server.

### 2. `manage` and `all` are not special-cased

They are ordinary index entries that every lookup merges with. One rule,
`manage:all`, is an administrator's entire grant:

```dart
ability.can('anything', 'Whatever');   // true
```

Which is why a permission check written as `permissions.contains('read:User')`
locks out precisely the account allowed to do everything, and nobody else.

### 3. Asking about a type is a different question from asking about an instance

```dart
ability.can('update', 'Article');   // is there ANY article I may update?
ability.can('update', article);     // may I update this one?
```

With no instance there is nothing to evaluate conditions against, so a
permitting rule answers **yes** — do not hide the menu item — while a
forbidding rule answers **no** only if its conditions restrict nothing.
Otherwise "you cannot edit articles you did not write" would read as "you
cannot edit articles".

---

## Declare your subject types

CASL.js reads `object.constructor.name`. The Dart equivalent is
`runtimeType.toString()`, and **`--obfuscate` renames it** — so a direct
translation authorises correctly in debug and silently differently in the build
that ships.

Declare the name instead. Either on the class:

```dart
class Article with CaslSubject {
  @override
  String get caslSubjectType => 'Article';
}
```

…or at the call site, for types you do not own:

```dart
ability.can('update', subject('Article', json));
```

`runtimeType` remains as a last resort, and is documented as one.

## Matching against your own models

Conditions read from a `Map` out of the box. To match a model directly, add
`CaslRecord`:

```dart
class Article with CaslSubject, CaslRecord {
  Article(this.authorId);
  final String authorId;

  @override
  String get caslSubjectType => 'Article';

  @override
  Object? caslField(String name) => switch (name) {
    'authorId' => authorId,
    _ => null,
  };
}
```

The switch is written by hand on purpose: generated field names would follow
your Dart identifiers rather than the names the server writes rules about, and
those are allowed to differ.

---

## Conditions

MongoDB-shaped, and the same fourteen operators CASL.js ships with:

`$eq` `$ne` `$lt` `$lte` `$gt` `$gte` `$in` `$nin` `$all` `$size` `$regex`
`$options` `$elemMatch` `$exists`

```dart
conditions: {
  'authorId': userId,
  'status': {r'$in': ['draft', 'review']},
  'views': {r'$gte': 100},
}
```

There are **no top-level operators** — no `$or`, no `$and`. A query is an
implicit AND of field tests, which is CASL's default exactly. An unsupported
operator throws rather than being ignored, because ignoring one turns a
restrictive rule into a permissive one. Add your own if your server really does
send more:

```dart
const MongoQueryParser().withOperators({r'$or': myOrParser});
```

Lists behave as they do in MongoDB, which is the part worth knowing:

```dart
// matches {'tags': ['draft', 'new']} — a list matches if it CONTAINS the value
conditions: {'tags': 'draft'}

// asks whether ANY comment is Ada's — a list mid-path is flattened
conditions: {'comments.author': 'ada'}
```

## Fields

```dart
RawRule.of(action: 'update', subject: 'Article', fields: ['title', 'body']);

ability.can('update', article, 'title');   // true
ability.can('update', article, 'salary');  // false
ability.can('update', article);            // true — "any field at all?"
```

`*` stays inside one segment and `**` crosses them, like a shell glob.
`address.*` also matches `address` itself.

For a form, ask for the list rather than one field at a time — a later rule can
take a field back, so the answers do not compose:

```dart
permittedFieldsOf(
  ability,
  'update',
  article,
  allFields: ['title', 'body', 'published'],
);
```

## Sharing rules with a CASL.js server

```dart
// server: res.json(packRules(ability.rules))
final rules = unpackRules(jsonDecode(body) as List<Object?>);
final ability = createMongoAbility(rules);
```

The packed form is an array per rule with the empty tail dropped, so the common
rule is two strings rather than six keys and their names:

```json
[["manage","all"],
 ["read,update","Article",{"authorId":7}],
 ["delete","Article",0,1,0,"published articles are kept"]]
```

Plain JSON works too — `RawRule.fromJson` / `toJson`.

## Refusing loudly

For the layer under the UI, where being asked to do something forbidden means
a bug or a stale screen rather than an expected answer:

```dart
ability.throwUnlessCan('delete', article);
// ForbiddenError: published articles are kept
```

The message prefers the forbidding rule's own `reason`, which is the difference
between "you cannot do that" and something the user can act on.
`errorUnlessCan` returns it instead of throwing, for putting the reason beside
a disabled button.

---

## Compared with CASL.js

Everything above matches `@casl/ability` v7, including the packed wire format.
Two deliberate differences, neither of which can change what a rule means:

| | Here | CASL.js |
|---|---|---|
| Subject types | declared (`CaslSubject` / `subject()`) | read from `constructor.name` |
| Field matcher | defaulted | must be supplied |

The first exists because Dart obfuscation makes the JS approach unsafe. The
second replaces a throw with the answer everyone was going to supply.

## Licence

MIT.
