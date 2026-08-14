import 'package:casl/src/ability.dart';
import 'package:casl/src/alias.dart';
import 'package:casl/src/conditions/condition.dart';
import 'package:casl/src/conditions/field_reader.dart';
import 'package:casl/src/conditions/interpreter.dart';
import 'package:casl/src/conditions/mongo_parser.dart';
import 'package:casl/src/deep_equals.dart';
import 'package:casl/src/matchers.dart';
import 'package:casl/src/raw_rule.dart';
import 'package:casl/src/subject.dart';

/// A rule's conditions, parsed once and ready to be asked.
final class MongoConditionsMatch implements ParsedConditions {
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
  @override
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
/// Supplying an [interpreter] configures the evaluation side completely, and
/// [read] and [equals] are then ignored — set them on the interpreter instead.
/// That is the seam for adding an operator: a parser entry turns `$name` into
/// a condition, an interpreter entry turns that condition into an answer, and
/// both halves are needed.
ConditionsMatcher mongoConditionsMatcher({
  MongoQueryParser parser = const MongoQueryParser(),
  FieldReader read = CaslFields.read,
  ValueEquality equals = deepEquals,
  ConditionInterpreter? interpreter,
}) {
  final effective =
      interpreter ?? ConditionInterpreter(read: read, equals: equals);

  return (conditions) => MongoConditionsMatch(
    conditions,
    parser: parser,
    interpreter: effective,
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
/// [detectSubjectType] only has to recognise the types it knows about —
/// returning null defers to [detectSubjectTypeByRuntimeType], so `subject()`
/// and `CaslSubject` keep working underneath it.
///
/// [strictJsEquality] compares condition values the way JavaScript's `===`
/// does, which is the one place this package deliberately answers differently
/// from CASL.js by default. See [caslStrictJsEquality] for what it changes and
/// when you want it.
/// [onUnparsableCondition] decides what happens when a rule carries an operator
/// this client does not know. It defaults to throwing, which is right for rules
/// written in Dart; set it to [UnparsableCondition.deny] for rules arriving
/// from a server that may have moved ahead of the app.
///
/// Supplying your own [parser] overrides that — a parser carries its own
/// policy, so configure it there instead.
Ability<A, S> createMongoAbility<A extends String, S extends String>(
  List<RawRule> rules, {
  MongoQueryParser? parser,
  FieldReader read = CaslFields.read,
  PartialDetectSubjectType? detectSubjectType,
  String anyActionName = anyAction,
  String anySubjectTypeName = anySubjectType,
  ResolveActions? resolveActions,
  bool strictJsEquality = false,
  UnparsableCondition onUnparsableCondition = UnparsableCondition.fail,
  ConditionInterpreter? interpreter,
}) => Ability<A, S>(
  rules,
  conditionsMatcher: mongoConditionsMatcher(
    parser:
        parser ??
        MongoQueryParser(onUnparsableCondition: onUnparsableCondition),
    read: read,
    equals: strictJsEquality ? caslStrictJsEquality : deepEquals,
    interpreter: interpreter,
  ),
  resolveActions: resolveActions,
  // The fallback is the *full* default, not `runtimeType.toString()`. Falling
  // back to the raw runtime type would silently disable `subject()` and
  // `CaslSubject` — the two mechanisms this package tells people to use — the
  // moment anyone supplied a detector for one of their own models.
  detectSubjectType: detectSubjectType == null
      ? null
      : (value) =>
            detectSubjectType(value) ?? detectSubjectTypeByRuntimeType(value),
  anyActionName: anyActionName,
  anySubjectTypeName: anySubjectTypeName,
);
