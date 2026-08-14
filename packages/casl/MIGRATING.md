# Migrating from 0.1.0

Every breaking change here came out of comparing this package against
`@casl/ability@7.0.1` case by case. Most are small; the two that touch real
call sites are `can.each` and `CanResult.reason`.

Nothing about the **wire format** changed. Rules a server sent to 0.1.0 mean the
same thing now.

---

## `casl`

### `can(['a', 'b'], …)` → `can.each(['a', 'b'], …)`

`AbilityBuilder.can` and `cannot` are callable objects rather than methods, so
the many-action form has its own entry point.

```diff
- builder.can(['update', 'delete'], 'Article', {'authorId': userId});
+ builder.can.each(['update', 'delete'], 'Article', {'authorId': userId});
```

Single-action calls are unchanged. CASL.js overloads that first parameter on
whether it is given a string or an array; Dart cannot, and typing it `Object`
to fake it would have thrown away the point of typing it at all.

### `Subject` → `ForcedSubject`

The wrapper `subject()` returns. Renamed because `Subject` collides with
`rxdart`'s, and an unused collision is fine right up until somebody uses one.

```diff
- final wrapped = subject('Article', json) as Subject;
+ final wrapped = subject('Article', json) as ForcedSubject;
```

`subject()` itself is unchanged, and most code never names the type.

### Field readers moved onto `CaslFields`

```diff
- readField(target, 'authorId')
+ CaslFields.read(target, 'authorId')

- readPath(target, 'author.id')
+ CaslFields.path(target, 'author.id')

- readParent(target, 'author.id')
+ CaslFields.parent(target, 'author.id')

- hasField(target, 'authorId')
+ CaslFields.has(target, 'authorId')
```

These are names an application is quite likely to want for itself, and a
package that forces `hide` clauses on a common import is a package people put
down.

### `alwaysTrue` / `alwaysFalse` → `Condition.always` / `Condition.never`

```diff
- if (condition == alwaysTrue) …
+ if (condition == Condition.always) …
```

### `oneOrMany`, `subjectValue`, `isSubjectType` are no longer exported

Internal chores that leaked. `RawRule.of` normalises the one-or-many shape for
you; the other two were only ever used by `Rule` to decide whether it had been
handed a type or an instance.

### `throwUnlessCan` no longer takes a trailing `message`

It needed a `null` placeholder for `field` to reach, and there is now a better
spelling:

```diff
- ability.throwUnlessCan('delete', article, null, 'You cannot delete posts');
+ ForbiddenError.from(ability)
+     .setMessage('You cannot delete posts')
+     .throwUnlessCan('delete', article);
```

`errorUnlessCan` keeps the parameter.

### Reading a bad rule now throws a `FormatException`

`RawRule.fromJson` and `unpackRules` used to leak whatever went wrong
underneath — an `ArgumentError`, and for a non-string `reason` a bare
`TypeError`. Neither is something a caller can be asked to catch: an `Error`
means "a programmer wrote this wrong", and there is no programmer involved in a
payload off a network.

```diff
  try {
    ability.update(unpackRules(payload));
- } on ArgumentError catch (error) {
+ } on FormatException catch (error) {
    …
  }
```

`ConditionFormatException` implements `FormatException` too, so one clause
covers the whole boundary.

### `AbilityBuilder.build()` defaults to `createMongoAbility`

It used to default to a bare `Ability`, which has no conditions matcher and so
threw on any rule carrying conditions. If you relied on that — and the only way
to rely on it was to have no conditional rules — nothing changes. Pass
`create:` for anything else.

### Behaviour that changed

None of these need a code change, but they change answers:

| | |
|---|---|
| `{'a.b': null}` no longer matches an object with no `a` at all | matches `@casl/ability`; we were the more permissive of the two |
| `$size` across a nested array path | now measures each element's own list rather than the flattened result |
| A `RegExp` inside `$in` | now applied rather than compared for equality |
| Nulls read through a list | no longer dropped — JSON has no `undefined`, so they were all being discarded |
| `"inverted": 1` from a server | now read as `true`; it used to read as `false`, turning a forbidding rule into a permitting one |
| `$options: 'g'`, `'y'`, `'d'` | tolerated rather than refused |
| A field query whose `$`-operator was not its first key | now caught rather than silently treated as a literal value |

---

## `casl_flutter`

### `CanResult.reason` means something different

It used to resolve through `ForbiddenError.message`, so it was never null when
disallowed — and `Tooltip(message: can.reason ?? '')`, straight out of the old
README, always rendered `Cannot execute "delete" on "Article"`.

`reason` is now the forbidding rule's **own words**, or null, which is what
`@casl/react` means by it. `CanResult.message` is the resolved text.

```diff
  CanBuilder(
    'delete',
    article,
    builder: (context, can) => Tooltip(
-     message: can.reason ?? '',      // always populated, usually noise
+     message: can.reason ?? '',      // now empty unless a rule spoke
      child: …,
    ),
  );
```

The line is the same; what it does is better. If you *want* the fallback, use
`can.message`.

---

## Worth adopting, though nothing forces you to

### Type your actions

```dart
extension type const AppAction(String wire) implements String {
  static const read = AppAction('read');
  static const delete = AppAction('delete');
}

typedef AppAbility = Ability<AppAction, AppSubject>;
typedef AppCan = Can<AppAction>;
```

`ability.can('reed', article)` then stops compiling. It costs nothing at
runtime — an `AppAction` *is* a `String` — and typed and untyped code
interoperate, so you can adopt it one screen at a time.

### Validate rules when they arrive

```dart
ability
  ..update(unpackRules(payload))
  ..validateRules();
```

Conditions compile lazily, and a rule checked only against a subject *type*
never compiles them at all — so a rule your build cannot read can pass
`can('read', 'Article')` and only throw when somebody opens a list.
`validateRules` moves that to a point you chose.

### Decide what an unfamiliar rule should do

```dart
createMongoAbility(rules, onUnparsableCondition: UnparsableCondition.deny);
```

Right when the rules come from a server that may have moved ahead of the app: a
rule it cannot read grants nothing, instead of throwing.
