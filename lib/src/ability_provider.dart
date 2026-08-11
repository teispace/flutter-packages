import 'package:casl/casl.dart';
import 'package:flutter/widgets.dart';

/// Puts an ability in the tree, and rebuilds what depends on it when the
/// rules change.
///
/// ```dart
/// AbilityProvider(
///   ability: ability,
///   child: MaterialApp(...),
/// )
/// ```
///
/// ## Why this listens rather than just holding a value
///
/// An ability is *mutable* — `ability.update(rules)` replaces the grant in
/// place, which is what a token refresh does when a role has changed. Holding
/// it in a plain `InheritedWidget` would leave every screen drawing the old
/// permissions until something unrelated happened to rebuild it, which is the
/// bug where a demoted user keeps their buttons until they navigate.
///
/// So this subscribes to the ability's own `updated` event and republishes.
/// Nothing above it has to know, and nothing below it has to remember.
class AbilityProvider extends StatefulWidget {
  /// Provides [ability] to [child] and everything under it.
  const AbilityProvider({
    required this.ability,
    required this.child,
    super.key,
  });

  /// The ability to publish.
  final PureAbility ability;

  /// The subtree that may ask about it.
  final Widget child;

  /// The nearest ability above [context].
  ///
  /// Throws when there is none, naming what is missing — a permission check
  /// that silently answers "no" because nobody provided an ability is
  /// indistinguishable from one that answers "no" because the user is not
  /// allowed, and the second is a support ticket while the first is a bug.
  ///
  /// Set [listen] to false to read it without subscribing, in a callback or an
  /// `initState` where a rebuild is neither wanted nor possible.
  static PureAbility of(BuildContext context, {bool listen = true}) {
    final ability = maybeOf(context, listen: listen);
    if (ability != null) return ability;

    throw FlutterError.fromParts([
      ErrorSummary('No AbilityProvider found above this widget.'),
      ErrorDescription(
        'Something asked what the user is allowed to do, but no ability has '
        'been provided, so the honest answer is "unknown" rather than "no".',
      ),
      ErrorHint(
        'Wrap your app — or at least the signed-in part of it — in an '
        'AbilityProvider.',
      ),
      context.describeElement('The widget that asked was'),
    ]);
  }

  /// The nearest ability above [context], or null when there is none.
  ///
  /// For code that genuinely works either way: a shared widget used both
  /// inside an authenticated shell and on a sign-in screen, say.
  static PureAbility? maybeOf(BuildContext context, {bool listen = true}) {
    final scope = listen
        ? context.dependOnInheritedWidgetOfExactType<AbilityScope>()
        : context.getInheritedWidgetOfExactType<AbilityScope>();

    return scope?.ability;
  }

  @override
  State<AbilityProvider> createState() => _AbilityProviderState();
}

class _AbilityProviderState extends State<AbilityProvider> {
  late VoidCallback _unsubscribe;

  /// Bumped on every rule change, because the ability itself is the same
  /// object before and after — identity cannot tell the two apart.
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(AbilityProvider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ability == widget.ability) return;

    _unsubscribe();
    _subscribe();
    _revision++;
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  void _subscribe() {
    _unsubscribe = widget.ability.on('updated', (_) {
      // Guarded because rules can arrive from anywhere — a websocket, a token
      // refresh — including after this subtree has gone.
      if (mounted) setState(() => _revision++);
    });
  }

  @override
  Widget build(BuildContext context) => AbilityScope(
    ability: widget.ability,
    revision: _revision,
    child: widget.child,
  );
}

/// The inherited widget [AbilityProvider] publishes.
///
/// Public only so that a test can find it, and so an app with its own state
/// management can publish an ability without using [AbilityProvider] — in
/// which case it owns the job of bumping [revision] when the rules change.
class AbilityScope extends InheritedWidget {
  /// Publishes [ability] at [revision].
  const AbilityScope({
    required this.ability,
    required this.revision,
    required super.child,
    super.key,
  });

  /// What the subtree may ask.
  final PureAbility ability;

  /// Changes whenever the rules do.
  final int revision;

  @override
  bool updateShouldNotify(AbilityScope oldWidget) =>
      oldWidget.ability != ability || oldWidget.revision != revision;
}
