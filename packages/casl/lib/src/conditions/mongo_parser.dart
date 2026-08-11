import 'package:casl/src/conditions/condition.dart';
import 'package:meta/meta.dart';

/// Everything an operator needs in order to parse itself.
///
/// A record rather than five positional parameters, because two of them are
/// rarely used and an operator table is something people extend.
@immutable
final class OperatorCall {
  /// Creates the call.
  const OperatorCall({
    required this.name,
    required this.value,
    required this.parser,
    this.field,
    this.siblings = const {},
  });

  /// The operator as written, `$gte` and so on.
  final String name;

  /// What it was given.
  final Object? value;

  /// The field being described, or null at the top level.
  final String? field;

  /// The other keys beside it. `$regex` reads `$options` from here.
  final Map<String, Object?> siblings;

  /// For operators that contain a nested query, such as `$elemMatch`.
  final MongoQueryParser parser;
}

/// How one `$operator` becomes a [Condition].
typedef OperatorParser = Condition Function(OperatorCall call);

/// Turns a MongoDB-shaped query into a [Condition] tree.
///
/// ```dart
/// const MongoQueryParser().parse({'authorId': 7, 'views': {r'$gte': 100}});
/// ```
///
/// ## What the default set does and does not include
///
/// Fourteen **field** operators, and no top-level ones. That is CASL.js's
/// default exactly, and it surprises people: `$or` and `$and` are *not*
/// available unless you add them, so a plain query is an implicit AND of field
/// tests. Adding them is one entry — see [withOperators] — but think first
/// about whether the server sending these rules also understands them, because
/// a condition one side evaluates differently is worse than one neither does.
@immutable
final class MongoQueryParser {
  /// Creates a parser over [operators].
  const MongoQueryParser({this.operators = defaultOperators});

  /// The operator table, keyed by the `$name` as it appears in a query.
  final Map<String, OperatorParser> operators;

  /// The same parser with [extra] added, replacing any of the same name.
  MongoQueryParser withOperators(Map<String, OperatorParser> extra) =>
      MongoQueryParser(operators: {...operators, ...extra});

  /// Parses [query] into a condition tree.
  ///
  /// [field] is set when parsing a nested query about one field, which is what
  /// `$elemMatch` does over a list of scalars.
  Condition parse(Map<String, Object?> query, {String? field}) {
    final conditions = <Condition>[];

    for (final entry in query.entries) {
      final key = entry.key;
      final value = entry.value;

      if (key.startsWith(r'$')) {
        _add(conditions, _run(key, value, field, query));
        continue;
      }

      if (value is Map<String, Object?> && _hasOperators(value)) {
        for (final operator in value.entries) {
          if (!operators.containsKey(operator.key)) {
            throw UnsupportedError(
              'the query for "$key" may hold only operators or a plain '
              'value, but it has "${operator.key}"',
            );
          }
          _add(conditions, _run(operator.key, operator.value, key, value));
        }
        continue;
      }

      conditions.add(FieldCondition('eq', key, value));
    }

    if (conditions.length == 1) return conditions.single;
    return CompoundCondition('and', conditions);
  }

  Condition _run(
    String name,
    Object? value,
    String? field,
    Map<String, Object?> siblings,
  ) {
    final parser = operators[name];
    if (parser == null) throw UnsupportedError('unsupported operator "$name"');

    return parser(
      OperatorCall(
        name: name,
        value: value,
        field: field,
        siblings: siblings,
        parser: this,
      ),
    );
  }

  /// `$options` parses to nothing — it modifies the `$regex` beside it.
  static void _add(List<Condition> conditions, Condition condition) {
    if (condition != alwaysTrue) conditions.add(condition);
  }

  /// Whether a field's value is a set of operators rather than a plain value.
  ///
  /// Only the *first* key decides, which is MongoDB's own rule. It looks odd
  /// until you meet `{$gt: 1, stray: 2}` — mixing the two is a mistake, and
  /// reading it as operators makes the error name the stray key.
  static bool _hasOperators(Map<String, Object?> value) =>
      value.isNotEmpty && value.keys.first.startsWith(r'$');
}

/// The field operators CASL.js ships with, and only those.
///
/// Deliberately not a superset. A rule written against a client that
/// understands more than its server does behaves differently depending on who
/// evaluates it, which is the failure this package exists to avoid.
const Map<String, OperatorParser> defaultOperators = {
  r'$eq': _eq,
  r'$ne': _ne,
  r'$lt': _lt,
  r'$lte': _lte,
  r'$gt': _gt,
  r'$gte': _gte,
  r'$in': _in,
  r'$nin': _nin,
  r'$all': _all,
  r'$size': _size,
  r'$regex': _regex,
  r'$options': _options,
  r'$elemMatch': _elemMatch,
  r'$exists': _exists,
};

Condition _eq(OperatorCall c) => FieldCondition('eq', c.field, c.value);
Condition _ne(OperatorCall c) => FieldCondition('ne', c.field, c.value);

Condition _lt(OperatorCall c) => FieldCondition('lt', c.field, _orderable(c));
Condition _lte(OperatorCall c) => FieldCondition('lte', c.field, _orderable(c));
Condition _gt(OperatorCall c) => FieldCondition('gt', c.field, _orderable(c));
Condition _gte(OperatorCall c) => FieldCondition('gte', c.field, _orderable(c));

Condition _in(OperatorCall c) => FieldCondition('in', c.field, _list(c));
Condition _nin(OperatorCall c) => FieldCondition('nin', c.field, _list(c));
Condition _all(OperatorCall c) => FieldCondition('all', c.field, _list(c));

Condition _size(OperatorCall c) => c.value is int
    ? FieldCondition('size', c.field, c.value)
    : throw ArgumentError.value(c.value, c.name, 'expects a whole number');

Condition _exists(OperatorCall c) => c.value is bool
    ? FieldCondition('exists', c.field, c.value)
    : throw ArgumentError.value(c.value, c.name, 'expects true or false');

Condition _regex(OperatorCall c) =>
    FieldCondition('regex', c.field, _regExp(c));

/// Parses to nothing: it configures the `$regex` beside it rather than being
/// a test of its own.
Condition _options(OperatorCall c) => alwaysTrue;

Condition _elemMatch(OperatorCall c) {
  final query = c.value;
  if (query is! Map<String, Object?>) {
    throw ArgumentError.value(query, c.name, 'expects a nested query');
  }

  // Operators written directly inside `$elemMatch` describe each *element*
  // rather than a field of it, which is how a list of scalars is matched:
  // `{scores: {$elemMatch: {$gte: 80}}}`.
  return FieldCondition('elemMatch', c.field, c.parser.parse(query));
}

Object _orderable(OperatorCall c) => switch (c.value) {
  final num v => v,
  final String v => v,
  final DateTime v => v,
  _ => throw ArgumentError.value(
    c.value,
    c.name,
    'expects something orderable — a number, a string or a DateTime',
  ),
};

List<Object?> _list(OperatorCall c) => c.value is List<Object?>
    ? c.value! as List<Object?>
    : throw ArgumentError.value(c.value, c.name, 'expects a list');

/// Builds a Dart [RegExp] from Mongo's pattern-and-flags pair.
///
/// Dart has no `x` (extended) mode, so asking for one throws rather than
/// quietly matching something else. A regular expression that silently means
/// something different is exactly the authorisation bug nobody finds.
RegExp _regExp(OperatorCall c) {
  final pattern = c.value;
  if (pattern is RegExp) return pattern;
  if (pattern is! String) {
    throw ArgumentError.value(pattern, c.name, 'expects a pattern string');
  }

  final options = c.siblings[r'$options'];
  final flags = options is String ? options : '';
  for (final flag in flags.split('')) {
    if (!'imsu'.contains(flag)) {
      throw ArgumentError.value(
        flags,
        r'$options',
        'Dart regular expressions have no "$flag" flag',
      );
    }
  }

  return RegExp(
    pattern,
    caseSensitive: !flags.contains('i'),
    multiLine: flags.contains('m'),
    dotAll: flags.contains('s'),
    unicode: flags.contains('u'),
  );
}
