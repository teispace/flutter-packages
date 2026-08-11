import 'package:casl/casl.dart';
import 'package:casl_flutter/src/context_extensions.dart';
import 'package:flutter/widgets.dart';

/// Shows [child] only when the action is permitted.
///
/// ```dart
/// Can('delete', article, child: DeleteButton(article: article))
/// ```
///
/// Rebuilds when the rules change, so a user whose role is revoked mid-session
/// loses the control without having to navigate.
///
/// ## Hiding is not always the right answer
///
/// A control that vanishes is a control the user cannot ask about. Where they
/// have reason to expect one — an owner looking at somebody else's document,
/// an account that has run out of seats — a disabled control that explains
/// itself prevents the support ticket a missing one causes. Use [otherwise] to
/// put something in its place, or [CanBuilder] to keep the control and disable
/// it.
class Can extends StatelessWidget {
  /// Shows [child] when [action] is permitted on [subject].
  ///
  /// [subject] may be a subject type — `Can('create', 'Article', ...)` — or an
  /// instance, which asks the more precise question. It is positional and
  /// required rather than optional because Dart forbids mixing optional
  /// positional parameters with named ones; pass `null` for an ability whose
  /// rules name no subjects.
  const Can(
    this.action,
    this.subject, {
    required this.child,
    this.field,
    this.otherwise,
    this.not = false,
    super.key,
  });

  /// What is being attempted.
  final String action;

  /// What it is being attempted on — a subject type, or an instance.
  final Object? subject;

  /// One field of it, when the question is that narrow.
  final String? field;

  /// Shown when permitted.
  final Widget child;

  /// Shown when not. Nothing at all by default.
  final Widget? otherwise;

  /// Inverts the question, so [child] shows when the action is *forbidden*.
  ///
  /// For the copy that only makes sense to someone who cannot do the thing —
  /// an upgrade prompt, a "read only" badge — where writing it the other way
  /// round would put the real content in [otherwise] and read backwards.
  final bool not;

  @override
  Widget build(BuildContext context) {
    final allowed = context.ability.can(action, subject, field);

    return allowed != not ? child : otherwise ?? const SizedBox.shrink();
  }
}

/// The answer, and why, handed to a [CanBuilder].
@immutable
final class CanResult {
  /// Creates the answer.
  const CanResult({required this.allowed, required this.ability, this.refusal});

  /// Whether the action is permitted.
  final bool allowed;

  /// Why not, when it is not.
  ///
  /// Carries the forbidding rule's own words where it gave any. Null whenever
  /// [allowed] is true.
  final ForbiddenError? refusal;

  /// The ability that answered, for a question this widget does not express.
  final Ability ability;

  /// The message to show, or null when there is nothing to explain.
  String? get reason => refusal?.message;
}

/// Builds either way, told whether the action is permitted.
///
/// The usually-better alternative to hiding a control. The builder is handed
/// the reason as well as the answer, which is the difference between a
/// greyed-out button and one that says why:
///
/// ```dart
/// CanBuilder(
///   'delete',
///   article,
///   builder: (context, can) => Tooltip(
///     message: can.reason ?? '',
///     child: FilledButton(
///       onPressed: can.allowed ? () => delete(article) : null,
///       child: const Text('Delete'),
///     ),
///   ),
/// )
/// ```
class CanBuilder extends StatelessWidget {
  /// Builds with the answer to "may [action] be done to [subject]".
  const CanBuilder(
    this.action,
    this.subject, {
    required this.builder,
    this.field,
    super.key,
  });

  /// What is being attempted.
  final String action;

  /// What it is being attempted on.
  final Object? subject;

  /// One field of it, when the question is that narrow.
  final String? field;

  /// Called with the answer, again whenever the rules change.
  final Widget Function(BuildContext context, CanResult can) builder;

  @override
  Widget build(BuildContext context) {
    final ability = context.ability;
    final refusal = ability.errorUnlessCan(action, subject, field);

    return builder(
      context,
      CanResult(
        allowed: refusal == null,
        refusal: refusal,
        ability: ability,
      ),
    );
  }
}
