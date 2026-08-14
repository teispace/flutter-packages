import 'package:casl/casl.dart';
import 'package:flutter/foundation.dart';

/// An [Ability] as a [Listenable], for the state-management package you
/// already use.
///
/// `AbilityProvider` is enough on its own. This is for the applications that
/// already have somewhere for shared state to live and would rather the ability
/// lived there too — Provider, Riverpod, Bloc and `ValueListenableBuilder` all
/// speak `Listenable`, and none of them speak `ability.on('updated', …)`.
///
/// ```dart
/// // Provider
/// ChangeNotifierProvider(create: (_) => AbilityNotifier(ability));
///
/// // Riverpod
/// final abilityProvider = ChangeNotifierProvider(
///   (ref) => AbilityNotifier(ability),
/// );
///
/// // no package at all
/// ListenableBuilder(
///   listenable: notifier,
///   builder: (context, _) => Text('${notifier.can('read', 'Article')}'),
/// );
/// ```
///
/// It does not own the ability. Disposing the notifier stops it listening; the
/// ability carries on, because it usually outlives every screen that watches it
/// and is replaced only at sign-in and sign-out.
class AbilityNotifier<A extends String, S extends String>
    extends ChangeNotifier {
  /// Listens to [ability] and notifies whenever its rules change.
  AbilityNotifier(this.ability) {
    _unsubscribe = ability.on('updated', (_) => notifyListeners());
  }

  /// The ability being watched. Ask it anything this class does not forward.
  final Ability<A, S> ability;

  late final Unsubscribe _unsubscribe;

  /// Whether [action] is permitted on [subject]. See [Ability.can].
  bool can(A action, [Object? subject, String? field]) =>
      ability.can(action, subject, field);

  /// The opposite of [can].
  bool cannot(A action, [Object? subject, String? field]) =>
      ability.cannot(action, subject, field);

  /// Why [action] is refused, or null when it is not.
  ///
  /// The rule's own words where it gave any — what turns a disabled button into
  /// one that explains itself.
  ForbiddenError? forbidden(A action, [Object? subject, String? field]) =>
      ability.errorUnlessCan(action, subject, field);

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }
}
