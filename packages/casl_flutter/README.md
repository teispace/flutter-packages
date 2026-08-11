# casl_flutter

Flutter bindings for [`casl`](https://pub.dev/packages/casl) — an ability in
the widget tree, so a screen draws what the user may actually do.

```dart
AbilityProvider(
  ability: ability,
  child: MaterialApp(...),
);
```

```dart
// hide it
Can('delete', article, child: DeleteButton(article: article));

// or keep it and say why not, which is usually kinder
CanBuilder(
  'delete',
  article,
  builder: (context, can) => Tooltip(
    message: can.reason ?? '',
    child: FilledButton(
      onPressed: can.allowed ? () => delete(article) : null,
      child: const Text('Delete'),
    ),
  ),
);

// or just ask
if (context.can('create', 'Article')) const NewArticleButton(),
```

`package:casl` is re-exported, so one import covers both.

---

## Contents

- [Install](#install)
- [Providing an ability](#providing-an-ability)
- [It follows a change of rules](#it-follows-a-change-of-rules)
- [Hiding, disabling, and explaining](#hiding-disabling-and-explaining)
- [Asking from anywhere](#asking-from-anywhere)
- [Field-level UI](#field-level-ui)
- [Guarding a route](#guarding-a-route)
- [Testing a permission-aware screen](#testing-a-permission-aware-screen)
- [API reference](#api-reference)
- [Compared with @casl/react](#compared-with-caslreact)

---

## Install

```yaml
dependencies:
  casl_flutter: ^0.1.0
```

```dart
import 'package:casl_flutter/casl_flutter.dart';
```

---

## Providing an ability

Put it above everything that might ask — usually the whole app, or the
signed-in part of it:

```dart
class App extends StatelessWidget {
  const App({required this.ability, super.key});

  final Ability ability;

  @override
  Widget build(BuildContext context) => AbilityProvider(
    ability: ability,
    child: MaterialApp.router(routerConfig: router),
  );
}
```

Build the ability from whatever your server sent:

```dart
final ability = createMongoAbility(
  unpackRules(json['rules'] as List<Object?>),
);
```

Asking with no provider above throws a `FlutterError` naming what is missing.
Answering "no" would be indistinguishable from a real refusal, and one of those
is a bug while the other is a support ticket. Use `AbilityProvider.maybeOf` for
a widget genuinely used on both sides of a sign-in.

---

## It follows a change of rules

`AbilityProvider` **listens** to the ability rather than only holding it. An
ability is mutable: `update(rules)` replaces the grant in place, which is what
a token refresh does when a role has changed.

```dart
// somewhere in your refresh handler
ability.update(unpackRules(response['rules'] as List<Object?>));
// buttons appear and disappear; nothing has to navigate
```

Without that, a demoted user keeps their controls until something unrelated
happens to rebuild the screen — and the screen they are staring at is exactly
the one that will not.

Replacing the ability object works too, which is what signing in as somebody
else does:

```dart
AbilityProvider(ability: abilityForNewUser, child: ...)
```

---

## Hiding, disabling, and explaining

Three shapes, and the middle one is right more often than people expect.

### Hide it

```dart
Can('create', 'Article', child: const NewArticleButton());
```

Right when the user has no reason to expect the control — an admin-only section
of a settings page, a feature their plan does not include and never has.

### Say something else in its place

```dart
Can(
  'invite',
  'User',
  otherwise: const Text('Ask an administrator to invite people.'),
  child: const InviteButton(),
);
```

### Keep it, disable it, and explain

```dart
CanBuilder(
  'delete',
  article,
  builder: (context, can) => Tooltip(
    message: can.reason ?? '',
    child: IconButton(
      onPressed: can.allowed ? () => delete(article) : null,
      icon: const Icon(Icons.delete),
    ),
  ),
);
```

A control that vanishes is a control the user cannot ask about. Where they have
reason to expect one — an owner looking at somebody else's document, an account
that has run out of seats — a disabled control that explains itself prevents
the support ticket a missing one causes.

`can.reason` is whatever the forbidding rule said, written by whoever wrote the
rule. That may well be your server, in which case it arrives already in the
user's language.

### Show something *because* they cannot

```dart
Can(
  'invite',
  'User',
  not: true,
  child: const UpgradePrompt(),
);
```

For copy that only makes sense to someone who cannot do the thing. Writing it
the other way round would put the real content in `otherwise` and read
backwards.

---

## Asking from anywhere

```dart
context.can('read', article)          // bool
context.cannot('read', article)       // bool
context.forbidden('delete', article)  // ForbiddenError?, carrying the reason
context.ability                       // the ability itself, subscribing
context.readAbility()                 // …without subscribing
```

Everything except `readAbility` subscribes, so the widget rebuilds when the
rules change. That is what you want almost always. `readAbility` is for a
callback or an `initState`, where a rebuild is impossible and pointless — by
the time a tap is handled, the tap is over:

```dart
onPressed: () {
  final ability = context.readAbility();
  if (ability.can('delete', article)) delete(article);
},
```

---

## Field-level UI

`CanBuilder` hands you the ability as well as the answer, for questions these
widgets do not express:

```dart
CanBuilder(
  'update',
  article,
  builder: (context, can) => Column(
    children: [
      for (final field in permittedFieldsOf(
        can.ability,
        'update',
        article,
        allFields: Article.editableFields,
      ))
        FieldEditor(name: field),
    ],
  ),
);
```

Asking per field would give the right answer per field and the wrong list — a
later rule can take a field back, so the answers do not compose. See
[`casl`](https://pub.dev/packages/casl#field-level-rules).

---

## Guarding a route

There is no route widget here on purpose: every router expresses redirects
differently, and wrapping one would tie this package to it. A guard is a
function of the ability, which you already have:

```dart
// go_router
GoRoute(
  path: '/admin',
  redirect: (context, state) =>
      context.readAbility().can('manage', 'all') ? null : '/forbidden',
  builder: (context, state) => const AdminPage(),
);
```

Use `readAbility()` in a redirect — a router callback is not a build, so there
is nothing to subscribe. To re-evaluate redirects when rules change, feed your
router's `refreshListenable` from the same signal you use to call
`ability.update(...)`.

---

## Testing a permission-aware screen

Wrap the widget under test and pass the rules the case needs:

```dart
Future<void> pumpAs(WidgetTester tester, List<RawRule> rules) =>
    tester.pumpWidget(
      AbilityProvider(
        ability: createMongoAbility(rules),
        child: MaterialApp(home: ArticlePage(article: article)),
      ),
    );

testWidgets('an author sees the delete button', (tester) async {
  await pumpAs(tester, [
    RawRule.of(
      action: 'delete',
      subject: 'Article',
      conditions: {'authorId': 7},
    ),
  ]);

  expect(find.byIcon(Icons.delete), findsOneWidget);
});
```

To test that a screen *follows* a change of rules, keep the ability and update
it mid-test:

```dart
final ability = createMongoAbility(const []);
await tester.pumpWidget(...);

ability.update([RawRule.of(action: 'read', subject: 'Article')]);
await tester.pump();
```

---

## API reference

| | |
|---|---|
| `AbilityProvider` | puts an ability in the tree and republishes it when the rules change |
| `AbilityProvider.of` / `.maybeOf` | read it, with or without throwing |
| `AbilityScope` | the inherited widget, for an app that publishes its own |
| `Can` | shows `child` when permitted, `otherwise` when not; `not` inverts |
| `CanBuilder` | builds either way, given a `CanResult` |
| `CanResult` | `allowed`, `reason`, `refusal`, `ability` |
| `context.can` / `.cannot` | the question, subscribing |
| `context.forbidden` | why not — the rule's own words |
| `context.ability` / `.readAbility()` | the ability, with or without subscribing |

Everything else — rules, conditions, fields, queries, the CASL.js wire format —
is in [`casl`](https://pub.dev/packages/casl), and re-exported from here.

---

## Compared with @casl/react

| `@casl/react` | Here |
|---|---|
| `<AbilityProvider value={ability}>` | `AbilityProvider(ability: ...)` |
| `useAbility()` | `context.ability` |
| `<Can I="read" a="Post">` | `Can('read', 'Post', child: ...)` |
| `<Can not …>` | `Can(..., not: true)` |
| `<Can passThrough>` with a function child | `CanBuilder` |
| `{ isAllowed, ability, reason }` | `CanResult` |

React's prop aliases (`I` / `do`, `a` / `an` / `this` / `on` / `of`) exist to
make JSX read as a sentence. Dart's positional arguments already do, so there
is one spelling.

`useAbility` subscribes through `useSyncExternalStore`; `AbilityProvider` here
does the same job with a `StatefulWidget` and an `InheritedWidget`, so the
subscription is set up once at the provider rather than once per consumer.

---

## Licence

MIT.
