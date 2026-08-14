# casl_flutter

Flutter bindings for [`casl`](https://pub.dev/packages/casl) — an ability in the
widget tree, a `Can` widget, and `context.can(...)`.

So a screen draws what the user may actually do, and redraws when that changes.

```dart
final app = AbilityProvider(
  ability: ability,
  child: const MaterialApp(
    home: Can('create', 'Article', child: Text('New article')),
  ),
);
```

| | |
|---|---|
| **One question everywhere** | the same rules answer on the server, in a unit test and on screen |
| **Follows a role change** | `ability.update(...)` and every control redraws — no navigation, nothing to notify |
| **Type-safe at no cost** | pin the action type and `Can('reed', …)` stops compiling |
| **Fits your state management** | `AbilityNotifier` for Provider, Riverpod, Bloc — or nothing at all |

Everything is answered by `casl` itself, which is re-exported, so one import is
enough.

---

## Contents

- [Install](#install)
- [Providing an ability](#providing-an-ability)
- [It follows a change of rules](#it-follows-a-change-of-rules)
- [Hiding, disabling, and explaining](#hiding-disabling-and-explaining)
- [Asking from anywhere](#asking-from-anywhere)
- [Making a typo stop compiling](#making-a-typo-stop-compiling)
- [Somewhere else to keep the ability](#somewhere-else-to-keep-the-ability)
- [Field-level UI](#field-level-ui)
- [Guarding a route](#guarding-a-route)
- [Testing a permission-aware screen](#testing-a-permission-aware-screen)
- [API reference](#api-reference)
- [Compared with @casl/react](#compared-with-caslreact)

---

## Install

```yaml
dependencies:
  casl_flutter: ^1.0.0
```

```dart
import 'package:casl_flutter/casl_flutter.dart';
```

`casl` comes with it and is re-exported — you do not need it in your pubspec.

---

## Providing an ability

Wrap the part of the app that needs to ask. Usually that is all of it:

```dart
void main() {
  final ability = createMongoAbility(const []);

  runApp(
    AbilityProvider(
      ability: ability,
      child: const MaterialApp(home: Scaffold()),
    ),
  );
}
```

Reading it, with or without subscribing:

```dart
Widget readIt(BuildContext context) {
  context.ability;                              // subscribes: rebuilds on change
  AbilityProvider.of(context, listen: false);   // does not
  AbilityProvider.maybeOf(context);             // null when there is none

  return const SizedBox.shrink();
}
```

`AbilityProvider.of` throws when there is none, and says so in as many words. A
check that silently answers "no" because nobody provided an ability is
indistinguishable from one that answers "no" because the user is not allowed —
and the second is a support ticket while the first is a bug.

---

## It follows a change of rules

An ability is mutable. Replace the grant and everything below redraws:

```dart
void signIn(Ability current, List<RawRule> rules) {
  current.update(rules);
}
```

That is the whole of it — no navigation, nothing to notify, no rebuilding the
provider. A user demoted mid-session loses their buttons where they stand.

Rules may change during a build, too — a screen that fetches on its first
frame, a locator that initialises lazily, a router redirect. The provider
notices and republishes at the end of the frame rather than throwing
*setState() called during build*.

---

## Hiding, disabling, and explaining

Four shapes, and the fourth is the one people forget.

### 1. Hide it

```dart
const hidden = Can('create', 'Article', child: Text('New article'));
```

Right for something the user has no reason to expect to be there.

### 2. Say something else in its place

```dart
const upsell = Can(
  'invite',
  'Member',
  otherwise: Text('Upgrade to invite teammates'),
  child: Text('Invite a teammate'),
);
```

### 3. Keep it, disable it, and say why

Usually the kindest. A control that vanishes is a control the user cannot ask
about, and a missing button raises a support ticket where a disabled one that
explains itself does not.

```dart
final explained = CanBuilder(
  'delete',
  article,
  builder: (context, can) => Tooltip(
    message: can.reason ?? '',
    child: FilledButton(
      onPressed: can.allowed ? () {} : null,
      child: const Text('Delete'),
    ),
  ),
);
```

`can.reason` is the **rule's own words**, and null when it gave none — so the
tooltip appears only when there is something worth reading. `can.message` is
that, or the default (`Cannot execute "delete" on "Article"`) if the rule said
nothing; useful in a log, rarely what you want in a tooltip.

There is deliberately no `not` on `CanBuilder`: it would invert `allowed` and
leave `reason` describing a refusal the builder had just been told did not
happen. `!can.allowed` says the same thing and cannot be misread.

### 4. Show something *because* they cannot

```dart
const badge = Can(
  'update',
  'Article',
  not: true,
  child: Chip(label: Text('Read only')),
);
```

For the copy that only makes sense to somebody who cannot do the thing. Writing
it the other way round would put the real content in `otherwise` and read
backwards.

---

## Asking from anywhere

```dart
Widget row(BuildContext context) {
  if (context.cannot('read', article)) return const SizedBox.shrink();

  return Column(
    children: [
      if (context.can('delete', article)) const Text('Delete'),
      Text(context.forbidden('publish', article)?.reason ?? 'Publish'),
    ],
  );
}
```

Each of these subscribes, so the widget rebuilds when the rules change. That is
what you want almost always. In a callback — where a rebuild is neither wanted
nor possible, because by then the tap is over — use `context.readAbility()`.

---

## Making a typo stop compiling

`Can('reed', article, …)` compiles, hides the control, and never tells you.
Pin the action type and it does not:

```dart
extension type const AppAction(String wire) implements String {
  static const read = AppAction('read');
  static const delete = AppAction('delete');
}

typedef AppCan = Can<AppAction>;
typedef AppCanBuilder = CanBuilder<AppAction>;
```

<!-- continues -->

```dart
const good = AppCan(AppAction.delete, 'Article', child: Text('Delete'));
```

<!-- continues -->

```dart
const bad = AppCan('reed', 'Article', child: Text('Delete'));  // ✗ no compile
```

Nothing changes at runtime: an `AppAction` *is* a `String`, so the same rules,
the same wire format and the same `AbilityProvider` serve typed and untyped
screens side by side. See `casl`'s documentation for declaring the vocabulary.

`context.can(…)` cannot be typed by this package — an extension method infers
its type argument from whatever it is given, so a raw string would always
satisfy it. Three lines in your app close that:

<!-- continues -->

```dart
extension AppAbilityContext on BuildContext {
  bool may(AppAction action, [Object? subject, String? field]) =>
      ability.can(action, subject, field);
}
```

---

## Somewhere else to keep the ability

`AbilityProvider` is enough on its own. If your app already has a place for
shared state, `AbilityNotifier` puts the ability there instead — Provider,
Riverpod, Bloc and `ListenableBuilder` all speak `Listenable`, and none of them
speak `ability.on('updated', …)`.

```dart
final watched = ListenableBuilder(
  listenable: notifier,
  builder: (context, _) => Text('${notifier.can('read', 'Article')}'),
);
```

It listens; it does not own. Disposing the notifier stops it listening, and the
ability carries on — it usually outlives every screen that watches it, and is
replaced only at sign-in and sign-out.

---

## Field-level UI

A form should draw the boxes the rules allow, rather than drawing them all and
refusing on submit:

```dart
Widget buildForm(BuildContext context) {
  final editable = permittedFieldsOf(
    context.ability,
    'update',
    article,
    allFields: const ['title', 'body', 'published'],
  );

  return Column(
    children: [
      for (final field in editable)
        TextField(decoration: InputDecoration(labelText: field)),
    ],
  );
}
```

And for one field at a time, `Can` takes a `field`:

```dart
const titleOnly = Can(
  'update',
  'Article',
  field: 'title',
  child: Text('Rename'),
);
```

---

## Guarding a route

Ask outside the tree — in a router redirect, an interceptor, a use case — with
the ability you already hold:

```dart
String? redirect(Ability current) =>
    current.can('read', 'Admin') ? null : '/forbidden';
```

Inside the tree, `context.readAbility()` is the same question without
subscribing.

Rules on a client are a **user-experience** control, not an enforcement
boundary: anyone can patch a binary and answer `true` to every check. The
server has to enforce the same rules independently — which is the reason this
package shares CASL's wire format rather than inventing one.

---

## Testing a permission-aware screen

Build the ability the test needs, provide it, and pump:

```dart
Widget wrap(Ability current, Widget child) => AbilityProvider(
  ability: current,
  child: MaterialApp(home: Scaffold(body: child)),
);
```

<!-- fragment: a widget test, which needs flutter_test rather than the app -->

```dart
testWidgets('an author sees the delete button', (tester) async {
  final ability = defineAbility((can, _) => can('delete', 'Article'));

  await tester.pumpWidget(
    wrap(ability, const Can('delete', 'Article', child: Text('Delete'))),
  );

  expect(find.text('Delete'), findsOneWidget);
});
```

Worth testing is the function that *distributes* rules — that a moderator gets
the moderator rules — rather than `can`, which is pure and belongs to `casl`.

---

## API reference

| | |
|---|---|
| `AbilityProvider` | puts an ability in the tree and republishes it when the rules change |
| `AbilityProvider.of` / `.maybeOf` | read it, with or without throwing |
| `AbilityScope` | the inherited widget, for an app that publishes its own |
| `AbilityNotifier` | the ability as a `ChangeNotifier`, for Provider, Riverpod or Bloc |
| `Can<A>` | shows `child` when permitted, `otherwise` when not; `not` inverts |
| `CanBuilder<A>` | builds either way, given a `CanResult` |
| `CanResult` | `allowed`, `reason`, `message`, `refusal`, `ability` |
| `context.can` / `.cannot` | the question, subscribing |
| `context.forbidden` | why not — the rule's own words |
| `context.ability` / `.readAbility()` | the ability, with or without subscribing |

Everything else — rules, conditions, fields, queries, the CASL.js wire format —
is in [`casl`](https://pub.dev/packages/casl), and re-exported from here.

---

## Compared with @casl/react

| `@casl/react` | Here |
|---|---|
| `<AbilityProvider value={ability}>` | `AbilityProvider(ability: …)` |
| `useAbility()` | `context.ability` |
| `<Can I="read" a="Post">` | `Can('read', 'Post', child: …)` |
| `<Can not …>` | `Can(…, not: true)` |
| `<Can passThrough>` with a function child | `CanBuilder` |
| `{ isAllowed, ability, reason }` | `CanResult` — `allowed`, `ability`, `reason` |
| — | `CanResult.message`, the resolved text when the rule said nothing |
| — | `Can<A>` / `CanBuilder<A>`, so a misspelled action stops compiling |
| — | `AbilityNotifier`, for the state-management package you already use |

React's prop aliases (`I` / `do`, `a` / `an` / `this` / `on` / `of`) exist to
make JSX read as a sentence. Dart's positional arguments already do, so there
is one spelling.

`useAbility` subscribes through `useSyncExternalStore`; `AbilityProvider` does
the same job with a `StatefulWidget` and an `InheritedWidget`, so the
subscription is set up once at the provider rather than once per consumer. One
consequence is worth knowing: `useSyncExternalStore` is safe against a rules
change arriving *during* a render and a `StatefulWidget` is not, so the
provider checks the scheduler phase and republishes at the end of the frame
when the framework is mid-build.

---

## Licence

MIT.
