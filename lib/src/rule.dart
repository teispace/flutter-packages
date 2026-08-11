import 'package:casl/src/matchers.dart';
import 'package:casl/src/raw_rule.dart';
import 'package:casl/src/subject.dart';

/// A [RawRule] compiled for asking questions of.
///
/// Holds the matchers the raw rule cannot: compiling conditions is the
/// expensive part, and a list screen asks the same rule once per row.
final class Rule {
  /// Compiles [origin].
  ///
  /// [priority] orders it against its siblings. Lower wins, and the ability
  /// assigns it — see `PureAbility.can` for why the last declared gets zero.
  Rule(
    this.origin, {
    required this.priority,
    ConditionsMatcher? conditionsMatcher,
    FieldsMatcher? fieldsMatcher,
    List<String> Function(List<String>)? resolveActions,
  }) : _conditionsMatcher = conditionsMatcher,
       _fieldsMatcher = fieldsMatcher,
       actions = resolveActions == null
           ? origin.actions
           : resolveActions(origin.actions) {
    if (origin.fields case final fields? when fields.isEmpty) {
      throw ArgumentError.value(
        origin,
        'rule',
        'the fields list cannot be empty — omit it to mean "every field"',
      );
    }
    if (origin.fields != null && fieldsMatcher == null) {
      throw ArgumentError.value(
        origin,
        'rule',
        'this rule restricts fields, but the ability has no fieldsMatcher',
      );
    }
    if (origin.conditions != null && conditionsMatcher == null) {
      throw ArgumentError.value(
        origin,
        'rule',
        'this rule has conditions, but the ability has no conditionsMatcher. '
            'Use createMongoAbility, or pass one to PureAbility.',
      );
    }
  }

  /// The rule this was compiled from, unchanged.
  final RawRule origin;

  /// The actions, with any aliases already expanded.
  final List<String> actions;

  /// Where this rule sits against its siblings. Lower wins.
  final int priority;

  final ConditionsMatcher? _conditionsMatcher;
  final FieldsMatcher? _fieldsMatcher;

  ConditionsMatch? _conditions;
  bool Function(String)? _fields;

  /// Whether the rule forbids rather than permits.
  bool get inverted => origin.inverted;

  /// Why it forbids, if it says.
  String? get reason => origin.reason;

  /// Whether [subject] satisfies this rule's conditions.
  ///
  /// ## The asymmetry that matters
  ///
  /// When the question is about a subject *type* rather than an instance —
  /// "can I update Articles at all?" — there is nothing to evaluate conditions
  /// against. A permitting rule answers **yes**, because there may well be an
  /// article you can update and refusing would hide the button for everyone. A
  /// forbidding rule answers **no** unless its conditions restrict nothing,
  /// because "you cannot update articles you did not write" must not be read as
  /// "you cannot update articles".
  bool matchesConditions(Object? subject) {
    final conditions = origin.conditions;
    if (conditions == null) return true;

    final value = subjectValue(subject);
    if (value == null || isSubjectType(value)) {
      if (!inverted) return true;
      return _compiledConditions(conditions).matchesEverything;
    }

    return _compiledConditions(conditions).matches(value);
  }

  /// Whether this rule covers [field].
  ///
  /// A null [field] asks "does this rule cover *any* field", which forbidding
  /// rules deliberately decline to answer: they take a field away rather than
  /// granting one, so letting one match here would end the search at a rule
  /// that was never going to permit anything.
  bool matchesField(String? field) {
    final fields = origin.fields;
    if (fields == null) return true;
    if (field == null) return !inverted;

    return (_fields ??= _fieldsMatcher!(fields))(field);
  }

  ConditionsMatch _compiledConditions(Map<String, Object?> conditions) =>
      _conditions ??= _conditionsMatcher!(conditions);

  @override
  String toString() => '$origin (priority $priority)';
}
