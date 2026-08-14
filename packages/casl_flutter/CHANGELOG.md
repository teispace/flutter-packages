# Changelog

## 1.0.0 · 2026-08-14

There are breaking changes — see
[`casl`'s migration guide](https://pub.dev/packages/casl), which covers both
packages. The one that touches real call sites here is `CanResult.reason`.

### Added

- **Typed widgets.** `Can<A>` and `CanBuilder<A>` are generic over the action
  type, so pinning it with a typedef makes a typo stop compiling:

  ```dart
  typedef AppCan = Can<AppAction>;

  AppCan(AppAction.delete, article, child: const DeleteButton());
  AppCan('reed', article, child: const DeleteButton());   // no longer compiles
  ```

  Nothing changes at runtime. An `AppAction` *is* a `String`, so one
  `AbilityProvider` serves typed and untyped screens side by side, and the rules
  travel over the wire unchanged.
- **`AbilityNotifier`**, the ability as a `ChangeNotifier`. Provider, Riverpod,
  Bloc and `ListenableBuilder` all speak `Listenable`; none of them speak
  `ability.on('updated', …)`. It listens without owning: disposing it stops it
  listening and leaves the ability alone.
- **`CanResult.message`**, the resolved text — see below.

### Fixed

- **A rules change during a build no longer throws.** `AbilityProvider` called
  `setState` straight from the ability's event, so a screen that fetched on its
  first frame, a locator that initialised lazily or a router redirect would
  raise *setState() or markNeedsBuild() called during build*. It now checks the
  scheduler phase and republishes at the end of the frame when the framework is
  mid-build. React's `useSyncExternalStore` is safe by construction; a
  `StatefulWidget` has to ask.
- **A provider may now be disposed while the ability is emitting** — the Flutter
  face of the `ConcurrentModificationError` fixed in `casl`. An update that
  tears the provider out of the tree disposes it, and disposal unsubscribes,
  from inside the event.

### Changed

- **`CanResult.reason` is now the forbidding rule's own words, or null.** It
  used to resolve through `ForbiddenError.message`, so it was never null when
  disallowed — and `Tooltip(message: can.reason ?? '')`, straight out of this
  README, always rendered `Cannot execute "delete" on "Article"`. `reason` now
  means what `@casl/react` means by it; `CanResult.message` is the resolved
  text for callers that want a fallback.

### Not changed, on purpose

- **`CanBuilder` still has no `not`.** It would invert `allowed` and leave
  `reason` describing a refusal the builder had just been told did not happen.
  `!can.allowed` says the same thing and cannot be misread.

## 0.1.0

- Initial release: `AbilityProvider`, `Can`, `CanBuilder`, and the
  `BuildContext` extensions.
