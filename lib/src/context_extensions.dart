import 'package:casl/casl.dart';
import 'package:casl_flutter/src/ability_provider.dart';
import 'package:flutter/widgets.dart';

/// Asking what the user may do, from anywhere with a [BuildContext].
///
/// ```dart
/// if (context.can('delete', article)) DeleteButton(article: article),
/// ```
///
/// Every one of these subscribes, so the widget rebuilds when the rules
/// change. That is the behaviour you want almost always — a demoted user
/// should lose the button without navigating — and [readAbility] is the way
/// out for the few places it is wrong.
extension AbilityContext on BuildContext {
  /// The nearest ability, subscribing to changes.
  PureAbility get ability => AbilityProvider.of(this);

  /// The nearest ability *without* subscribing.
  ///
  /// For a callback, an `initState`, or anywhere a rebuild is impossible:
  /// asking during a tap does not need the widget to redraw when the answer
  /// changes, because by then the tap is over.
  PureAbility readAbility() => AbilityProvider.of(this, listen: false);

  /// Whether [action] is permitted on [subject].
  ///
  /// [subject] may be a subject type — `context.can('create', 'Article')` —
  /// or an instance, which is a different and usually more precise question.
  /// See `PureAbility.can`.
  bool can(String action, [Object? subject, String? field]) =>
      ability.can(action, subject, field);

  /// The opposite of [can].
  bool cannot(String action, [Object? subject, String? field]) =>
      ability.cannot(action, subject, field);

  /// Why [action] is refused, or null when it is not.
  ///
  /// The reason a rule gave, if it gave one. This is what turns a disabled
  /// button into a helpful one:
  ///
  /// ```dart
  /// final refusal = context.forbidden('delete', article);
  /// return Tooltip(
  ///   message: refusal?.message ?? '',
  ///   child: IconButton(
  ///     onPressed: refusal == null ? () => delete(article) : null,
  ///     icon: const Icon(Icons.delete),
  ///   ),
  /// );
  /// ```
  ///
  /// Preferable to hiding the control whenever the user might reasonably
  /// expect it: a missing button raises a support ticket, a disabled one that
  /// explains itself does not.
  ForbiddenError? forbidden(String action, [Object? subject, String? field]) =>
      ability.errorUnlessCan(action, subject, field);
}
