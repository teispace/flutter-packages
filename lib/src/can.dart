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

  @override
  Widget build(BuildContext context) => context.can(action, subject, field)
      ? child
      : otherwise ?? const SizedBox.shrink();
}

/// Builds either way, told whether the action is permitted.
///
/// The usually-better alternative to hiding a control:
///
/// ```dart
/// CanBuilder(
///   'delete',
///   article,
///   builder: (context, allowed) => FilledButton(
///     onPressed: allowed ? () => delete(article) : null,
///     child: const Text('Delete'),
///   ),
/// )
/// ```
///
/// Reach for `context.forbidden(...)` inside the builder when the *reason*
/// would help — it carries whatever the forbidding rule said, which is the
/// difference between a greyed-out button and one that says why.
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
  ///
  /// Positional, matching Flutter's own builders — `ValueWidgetBuilder` and
  /// `AsyncWidgetBuilder` both pass their payload the same way, and a named
  /// parameter here would read worse at every call site.
  // ignore: avoid_positional_boolean_parameters
  final Widget Function(BuildContext context, bool allowed) builder;

  @override
  Widget build(BuildContext context) =>
      builder(context, context.can(action, subject, field));
}
