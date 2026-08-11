# casl_flutter

Flutter bindings for [`casl`](https://pub.dev/packages/casl) — an ability in the
widget tree, so a screen draws what the user may actually do.

```dart
AbilityProvider(
  ability: ability,
  child: MaterialApp(...),
);
```

```dart
// hide it
Can('delete', article, child: DeleteButton(article: article));

// or keep it and disable it, which is usually kinder
CanBuilder(
  'delete',
  article,
  builder: (context, allowed) => FilledButton(
    onPressed: allowed ? () => delete(article) : null,
    child: const Text('Delete'),
  ),
);

// or just ask
if (context.can('create', 'Article')) const NewArticleButton(),
```

`package:casl` is re-exported, so one import is enough.

---

## Install

```yaml
dependencies:
  casl_flutter: ^0.1.0
```

## It follows a change of rules

`AbilityProvider` listens to the ability rather than only holding it. When a
token refresh brings a changed role and you call `ability.update(rules)`, every
widget that asked a question rebuilds:

```dart
ability.update(unpackRules(response['rules'] as List<Object?>));
// buttons appear and disappear; nothing has to navigate
```

Without that, a demoted user keeps their controls until something unrelated
happens to rebuild the screen.

## Hiding is not always the right answer

A control that vanishes is a control the user cannot ask about. Where they have
reason to expect one — an owner looking at somebody else's document, an account
that has run out of seats — a disabled control that explains itself prevents
the support ticket a missing one causes.

```dart
final refusal = context.forbidden('delete', article);

Tooltip(
  message: refusal?.message ?? '',
  child: IconButton(
    onPressed: refusal == null ? () => delete(article) : null,
    icon: const Icon(Icons.delete),
  ),
);
```

`refusal.message` is whatever the forbidding rule said — written by whoever
wrote the rule, which may well be your server.

`Can` also takes an `otherwise` for the same reason:

```dart
Can(
  'invite',
  'User',
  otherwise: const Text('Ask an administrator to invite people.'),
  child: const InviteButton(),
);
```

## The API

| | |
|---|---|
| `AbilityProvider` | puts an ability in the tree and republishes it when the rules change |
| `Can` | shows a child when permitted, `otherwise` when not |
| `CanBuilder` | builds either way, told whether it is permitted |
| `context.can` / `.cannot` | the question, from anywhere below the provider |
| `context.forbidden` | why not — the rule's own words |
| `context.ability` | the ability itself, subscribing |
| `context.readAbility()` | the ability without subscribing, for callbacks |

Asking with no provider above throws a `FlutterError` naming what is missing.
Answering "no" would be indistinguishable from a real refusal, and one of those
is a bug while the other is a support ticket. Use `AbilityProvider.maybeOf` for
a widget genuinely used on both sides of a sign-in.

## Everything else

Rules, conditions, fields and the CASL.js wire format are documented in
[`casl`](https://pub.dev/packages/casl). This package adds only the wiring.

## Licence

MIT.
