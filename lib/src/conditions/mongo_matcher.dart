import 'package:casl/src/ability.dart';
import 'package:casl/src/conditions/condition.dart';
import 'package:casl/src/conditions/field_reader.dart';
import 'package:casl/src/conditions/interpreter.dart';
import 'package:casl/src/conditions/mongo_parser.dart';
import 'package:casl/src/matchers.dart';
import 'package:casl/src/raw_rule.dart';

/// A rule's conditions, parsed once and ready to be asked.
final class MongoConditionsMatch implements ConditionsMatch {
  /// Parses [conditions].
  MongoConditionsMatch(
    Map<String, Object?> conditions, {
    MongoQueryParser parser = const MongoQueryParser(),
    // A private field as an initializing formal — callers still write
    // `interpreter:`, because Dart exposes it under its public name.
    this._interpreter = const ConditionInterpreter(),
  }) : condition = parser.parse(conditions);

  /// The parsed tree, exposed so a query builder can walk it.
  ///
  /// This is what turns rules into a database query: an application that wants
  /// "select the articles this user may read" translates this rather than
  /// fetching everything and filtering in memory.
  final Condition condition;

  final ConditionInterpreter _interpreter;

  @override
  bool matches(Object? subject) => _interpreter.interpret(condition, subject);

  @override
  bool get matchesEverything =>
      condition is CompoundCondition &&
      (condition as CompoundCondition).operator == 'and' &&
      (condition as CompoundCondition).conditions.isEmpty;
}

/// Builds the conditions matcher, optionally over a custom parser or reader.
///
/// ```dart
/// final matcher = mongoConditionsMatcher(
///   read: (target, field) => (target as MyModel).field(field),
/// );
/// ```
ConditionsMatcher mongoConditionsMatcher({
  MongoQueryParser parser = const MongoQueryParser(),
  FieldReader read = readField,
}) {
  final interpreter = ConditionInterpreter(read: read);
  return (conditions) => MongoConditionsMatch(
    conditions,
    parser: parser,
    interpreter: interpreter,
  );
}

/// An ability that understands MongoDB-style conditions. The usual entry point.
///
/// ```dart
/// final ability = createMongoAbility([
///   RawRule.of(action: 'read', subject: 'Article'),
///   RawRule.of(
///     action: 'update',
///     subject: 'Article',
///     conditions: {'authorId': currentUserId},
///   ),
/// ]);
/// ```
///
/// The counterpart of CASL.js's function of the same name, and it accepts the
/// rules that one produces unchanged — which is the whole point: a server
/// computes the rules once and both halves of the product agree about them.
PureAbility createMongoAbility(
  List<RawRule> rules, {
  MongoQueryParser parser = const MongoQueryParser(),
  FieldReader read = readField,
  String? Function(Object value)? detectSubjectType,
  String anyActionName = 'manage',
  String anySubjectTypeName = 'all',
  List<String> Function(List<String>)? resolveActions,
}) => PureAbility(
  rules,
  conditionsMatcher: mongoConditionsMatcher(parser: parser, read: read),
  resolveActions: resolveActions,
  detectSubjectType: detectSubjectType == null
      ? null
      : (value) => detectSubjectType(value) ?? value.runtimeType.toString(),
  anyActionName: anyActionName,
  anySubjectTypeName: anySubjectTypeName,
);
