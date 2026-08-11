import 'package:casl/src/ability.dart';
import 'package:casl/src/raw_rule.dart';

/// Collects rules in the order they are written, then builds an ability.
///
/// ```dart
/// final builder = AbilityBuilder()
///   ..can('read', 'Article')
///   ..can(['update', 'delete'], 'Article', conditions: {'authorId': userId})
///   ..cannot('delete', 'Article', conditions: {'published': true})
///       .because('a published article cannot be deleted');
///
/// final ability = builder.build();
/// ```
///
/// **Order is meaning.** Rules are checked last-first, so each line overrides
/// the ones above it. Write the broad grant first and narrow it afterwards, the
/// way the example above does — that is the shape that reads correctly.
class AbilityBuilder {
  /// Starts an empty builder.
  AbilityBuilder();

  final List<RawRule> _rules = [];

  /// The rules collected so far, in the order they were written.
  List<RawRule> get rules => List.unmodifiable(_rules);

  /// Permits [action] on [subject].
  ///
  /// [action] and [subject] each take one value or a list. Omitting [subject]
  /// writes the rule about every subject type, which is how a claim-style
  /// ability — `can('read')` with no subjects at all — is expressed.
  RuleRef can(
    Object action, [
    Object? subject,
    Map<String, Object?>? conditions,
    Object? fields,
  ]) => _add(
    RawRule.of(
      action: action,
      subject: subject,
      fields: fields,
      conditions: conditions,
    ),
  );

  /// Forbids [action] on [subject].
  ///
  /// Only meaningful *after* something that permits it — a forbidding rule
  /// with nothing to override changes nothing, because the absence of a rule
  /// already refuses.
  RuleRef cannot(
    Object action, [
    Object? subject,
    Map<String, Object?>? conditions,
    Object? fields,
  ]) => _add(
    RawRule.of(
      action: action,
      subject: subject,
      fields: fields,
      conditions: conditions,
      inverted: true,
    ),
  );

  /// Builds an ability over everything collected.
  ///
  /// Pass [create] to build something other than a bare [PureAbility] —
  /// `createMongoAbility` being the usual one.
  T build<T extends PureAbility>({
    T Function(List<RawRule> rules)? create,
  }) => create == null ? PureAbility(rules) as T : create(rules);

  RuleRef _add(RawRule rule) {
    _rules.add(rule);
    return RuleRef._(this, _rules.length - 1);
  }
}

/// A handle on the rule just written, so a reason can be attached to it.
///
/// Returned rather than taken as a parameter because `.because(...)` reads as
/// a sentence, and because a reason is only ever wanted on a small minority of
/// rules — the ones a user will be shown.
final class RuleRef {
  const RuleRef._(this._builder, this._index);

  final AbilityBuilder _builder;
  final int _index;

  /// Explains why the rule forbids something.
  ///
  /// Surfaces as `ForbiddenError.message`, so it is user-facing copy: write it
  /// for the person who hit the wall, not for the log.
  void because(String reason) {
    final rule = _builder._rules[_index];
    _builder._rules[_index] = RawRule(
      actions: rule.actions,
      subjects: rule.subjects,
      fields: rule.fields,
      conditions: rule.conditions,
      inverted: rule.inverted,
      reason: reason,
    );
  }
}
