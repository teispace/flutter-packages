import 'package:casl/src/ability.dart';

/// Builds the message shown when something is refused.
typedef ForbiddenMessageBuilder = String Function(ForbiddenError error);

/// Thrown when an action is not permitted.
///
/// Carries what was refused rather than only that something was — the action,
/// the subject type, the field, and the [reason] the rule gave if it gave one.
/// That is the difference between "you cannot do that" and "you cannot do that
/// while the invoice is locked", and only the rule knows which.
final class ForbiddenError implements Exception {
  /// Creates the error. Usually thrown by [AbilityGuard.throwUnlessCan].
  ForbiddenError({
    required this.action,
    required this.subjectType,
    this.subject,
    this.field,
    this.reason,
    // A private field as an initializing formal — callers still write
    // `message:`, and the public getter folds in the fallbacks.
    this._message,
  });

  /// How a refusal with no [reason] is described.
  ///
  /// Global, and deliberately: the alternative is threading a formatter
  /// through every call site that might refuse, which is all of them. Set it
  /// once at startup. It is called at throw time, so reading the current
  /// locale inside it works.
  ///
  /// ```dart
  /// ForbiddenError.describe = (e) => t.errors.notAllowed(action: e.action);
  /// ```
  static ForbiddenMessageBuilder describe = _defaultDescribe;

  /// What was attempted.
  final String action;

  /// What it was attempted on, as a subject type.
  final String subjectType;

  /// The subject itself, when the check was about an instance.
  final Object? subject;

  /// The field, when the check was about one.
  final String? field;

  /// What the forbidding rule said, if it said anything.
  ///
  /// User-facing copy, written by whoever wrote the rule — which may well be
  /// the server, so it arrives already in the user's language or not at all.
  final String? reason;

  final String? _message;

  /// The message to show.
  ///
  /// An explicit message wins, then the rule's [reason], then [describe].
  /// Ordered by how much the writer knew: a message set at the call site knows
  /// the most, and the default knows only the action's name.
  String get message => _message ?? reason ?? describe(this);

  @override
  String toString() => 'ForbiddenError: $message';

  static String _defaultDescribe(ForbiddenError error) =>
      'Cannot execute "${error.action}" on "${error.subjectType}"';
}

/// Turns a permission check into a guard that throws.
///
/// For the places where a refusal is exceptional rather than expected — a use
/// case invoked from somewhere that should already have checked. Screens ask
/// [Ability.can] and draw accordingly; this is for the layer underneath,
/// where being asked to do something forbidden means a bug or a stale UI.
extension AbilityGuard on Ability {
  /// Throws a [ForbiddenError] unless [action] is permitted.
  ///
  /// ```dart
  /// ability.throwUnlessCan('delete', article);
  /// await repository.delete(article.id);
  /// ```
  ///
  /// [message] overrides both the rule's reason and the default, for a call
  /// site that knows better than either.
  void throwUnlessCan(
    String action, [
    Object? subject,
    String? field,
    String? message,
  ]) {
    final error = errorUnlessCan(action, subject, field, message);
    if (error != null) throw error;
  }

  /// The error [throwUnlessCan] would throw, or null when it would not.
  ///
  /// For code that wants to report a refusal rather than raise one — putting
  /// the message beside a disabled button, say.
  ForbiddenError? errorUnlessCan(
    String action, [
    Object? subject,
    String? field,
    String? message,
  ]) {
    final rule = relevantRuleFor(action, subject, field);
    if (rule != null && !rule.inverted) return null;

    return ForbiddenError(
      action: action,
      subjectType: detectSubjectType(subject),
      subject: subject,
      field: field,
      // Only a rule that actually forbade can explain itself. Reaching here
      // with no rule at all means nothing granted the action, and there is
      // nobody to ask why.
      reason: rule?.reason,
      message: message,
    );
  }
}
