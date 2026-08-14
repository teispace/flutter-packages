import 'package:casl/src/conditions/condition.dart';
import 'package:casl/src/fields/field_pattern.dart';
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
  /// assigns it — see `Ability.can` for why the last declared gets zero.
  Rule(
    this.origin, {
    required this.priority,
    ConditionsMatcher? conditionsMatcher,
    this._fieldsMatcher = defaultFieldsMatcher,
    List<String> Function(List<String>)? resolveActions,
  }) : _conditionsMatcher = conditionsMatcher,
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
    if (origin.conditions != null && conditionsMatcher == null) {
      throw ArgumentError.value(
        origin,
        'rule',
        'this rule has conditions, but the ability has no conditionsMatcher. '
            'Use createMongoAbility, or pass one to Ability.',
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
  final FieldsMatcher _fieldsMatcher;

  ConditionsMatch? _conditions;
  bool Function(String)? _fields;

  /// Whether the rule forbids rather than permits.
  bool get inverted => origin.inverted;

  /// Why it forbids, if it says.
  String? get reason => origin.reason;

  /// The subject types this rule is about.
  List<String> get subjects => origin.subjects;

  /// The fields it is limited to, or null for all of them.
  List<String>? get fields => origin.fields;

  /// Its conditions, unparsed.
  Map<String, Object?>? get conditions => origin.conditions;

  /// Its conditions *parsed*, or null when it has none.
  ///
  /// The counterpart of CASL.js's `rule.ast`, and the seam a query builder
  /// works through: `rulesToCondition` walks these to turn a grant into a
  /// database query, so a list screen fetches what the user may see rather
  /// than fetching everything and filtering it.
  ///
  /// Only available when the conditions matcher produces one — the built-in
  /// Mongo matcher does.
  Condition? get condition {
    if (origin.conditions == null) return null;
    final match = _compiledConditions(origin.conditions!);
    return match is ParsedConditions ? match.condition : null;
  }

  /// Compiles this rule's conditions now, rather than on the first check that
  /// needs them.
  ///
  /// Throws whatever the conditions matcher throws — a
  /// `ConditionFormatException` from the built-in one. See
  /// `RuleIndex.validateRules`, which is how you would normally reach this.
  void compileConditions() {
    final conditions = origin.conditions;
    if (conditions != null) _compiledConditions(conditions);
  }

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

    return (_fields ??= _fieldsMatcher(fields))(field);
  }

  ConditionsMatch _compiledConditions(Map<String, Object?> conditions) =>
      _conditions ??= _conditionsMatcher!(conditions);

  @override
  String toString() => '$origin (priority $priority)';
}
