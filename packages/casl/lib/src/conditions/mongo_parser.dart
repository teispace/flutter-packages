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

  /// Refuses the value this operator was given, honouring the parser's
  /// [MongoQueryParser.onUnparsableCondition].
  ///
  /// Use this rather than throwing directly, in a custom operator as much as in
  /// a built-in one: it is what lets a client configured to tolerate rules it
  /// cannot read deny them instead of dying.
  ///
  /// ```dart
  /// Condition parseMod(OperatorCall call) => call.value is List<int>
  ///     ? FieldCondition('mod', call.field, call.value)
  ///     : call.refuse('expects two whole numbers');
  /// ```
  Condition refuse(String message) =>
      parser.refuse(message, field: field, operator: name);
}

/// How one `$operator` becomes a [Condition].
typedef OperatorParser = Condition Function(OperatorCall call);

/// What to do with a condition the parser cannot make sense of.
///
/// The two cases are an operator it has never heard of, and a field query that
/// mixes operators with plain keys. Both mean the same thing in practice: a
/// rule arrived that this client cannot evaluate.
enum UnparsableCondition {
  /// Throw a [ConditionFormatException] naming what was wrong. **The default.**
  ///
  /// Right for rules written in Dart, where an unknown operator is a typo and
  /// a silent denial would be a bug nobody finds.
  fail,

  /// Parse it into [Condition.never], so the rule grants nothing.
  ///
  /// Right for rules arriving from a server that may have moved ahead of the
  /// client. A single unfamiliar rule then denies its own grant, instead of
  /// throwing from wherever [fail] first meets it.
  ///
  /// And where it first meets it is the problem: conditions compile lazily, and
  /// a rule checked only against a subject *type* never compiles them at all —
  /// so a rule this client cannot read can pass `can('read', 'Article')` and
  /// only throw when somebody opens a list. `RuleIndex.validateRules` forces
  /// the question at a point you choose.
  ///
  /// Denying rather than ignoring is deliberate: a condition nobody can
  /// evaluate must not be read as "no condition".
  deny,
}

/// Thrown when a rule's conditions cannot be parsed.
///
/// Carries enough to name the rule that caused it, which an `ArgumentError`
/// from four frames down does not.
///
/// A [FormatException], so one `on FormatException` catches everything that can
/// go wrong reading rules off a network — this, `RawRule.fromJson` and
/// `unpackRules` alike.
final class ConditionFormatException implements FormatException {
  /// Creates the exception.
  const ConditionFormatException(this.message, {this.field, this.operator});

  /// What was wrong, in a sentence.
  @override
  final String message;

  /// Unused. Conditions are parsed from a decoded map, not from text, so there
  /// is no source string and no offset into one.
  @override
  Object? get source => null;

  @override
  int get offset => -1;

  /// The field being described, when the failure was inside a field query.
  final String? field;

  /// The operator at fault, when there was one.
  final String? operator;

  @override
  String toString() {
    final where = [
      if (field != null) 'field "$field"',
      if (operator != null) 'operator "$operator"',
    ].join(', ');

    final at = where.isEmpty ? '' : ' ($where)';
    return 'ConditionFormatException: $message$at';
  }
}

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
  const MongoQueryParser({
    this.operators = defaultOperators,
    this.onUnparsableCondition = UnparsableCondition.fail,
  });

  /// The operator table, keyed by the `$name` as it appears in a query.
  final Map<String, OperatorParser> operators;

  /// What to do with a condition this parser cannot make sense of.
  ///
  /// Defaults to [UnparsableCondition.fail]. Set it to
  /// [UnparsableCondition.deny] when the rules come from a server that may
  /// know operators this client does not.
  final UnparsableCondition onUnparsableCondition;

  /// The same parser with [extra] added, replacing any of the same name.
  MongoQueryParser withOperators(Map<String, OperatorParser> extra) =>
      MongoQueryParser(
        operators: {...operators, ...extra},
        onUnparsableCondition: onUnparsableCondition,
      );

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

      final operators = _asFieldQuery(value);
      if (operators == null) {
        conditions.add(FieldCondition('eq', key, value));
        continue;
      }

      for (final operator in operators.entries) {
        _add(
          conditions,
          operator.key.startsWith(r'$')
              ? _run(operator.key, operator.value, key, operators)
              // A stray plain key beside an operator is a malformed rule
              // rather than an unknown one, but it fails for the same reason —
              // nobody can evaluate it — so it takes the same policy. CASL.js
              // raises here too.
              : refuse(
                  'a field query may hold only operators, not a plain key',
                  field: key,
                  operator: operator.key,
                ),
        );
      }
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
    if (parser == null) {
      return refuse('unsupported operator', field: field, operator: name);
    }

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

  /// Collects a parsed condition, dropping the ones that are not tests.
  ///
  /// `$options` is the case: it configures the `$regex` beside it rather than
  /// asserting anything of its own, so it parses to [Condition.always] and is
  /// discarded here. [Condition.never] is *not* discarded — a refusal has to
  /// survive into the tree, or the policy that produced it would mean nothing.
  static void _add(List<Condition> conditions, Condition condition) {
    if (condition != Condition.always) conditions.add(condition);
  }

  /// Applies [onUnparsableCondition] to something this parser cannot read.
  ///
  /// Either throws a [ConditionFormatException] or returns [Condition.never],
  /// depending on the policy. Custom operators should reach this through
  /// [OperatorCall.refuse] rather than throwing on their own, so that a client
  /// told to tolerate unreadable rules actually does.
  Condition refuse(String message, {String? field, String? operator}) {
    if (onUnparsableCondition == UnparsableCondition.deny) {
      return Condition.never;
    }
    throw ConditionFormatException(message, field: field, operator: operator);
  }

  /// The operator map inside a field's value, or null when it is a plain value.
  ///
  /// ## Why any `$` key decides, rather than the first
  ///
  /// A map is a *field query* if it mentions an operator anywhere, not only in
  /// its first entry. Reading only the first key meant that a stray plain key
  /// written *before* an operator was taken for a literal value and silently
  /// matched nothing, while the same mistake written after it was caught. Dart
  /// map literals preserve insertion order, so the behaviour depended on the
  /// order somebody happened to type.
  ///
  /// Unknown `$` operators still reach [_run], which is what keeps a typo loud
  /// instead of turning it into an equality test against a literal map. CASL.js
  /// decides by which operators it recognises, so it takes that second path
  /// silently; the difference is recorded in the README.
  static Map<String, Object?>? _asFieldQuery(Object? value) {
    // `Map<String, Object?>` alone would miss a `Map<dynamic, dynamic>`, which
    // is what a loosely typed decoder or `Map.from` produces — and missing it
    // would read the whole map as a literal value, with no error and a wrong
    // answer.
    if (value is! Map) return null;

    final entries = <String, Object?>{};
    var sawOperator = false;
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) return null;
      if (key.startsWith(r'$')) sawOperator = true;
      entries[key] = entry.value;
    }

    return sawOperator ? entries : null;
  }
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

/// The logical operators CASL leaves out, ready to be switched on.
///
/// ```dart
/// createMongoAbility(
///   rules,
///   parser: const MongoQueryParser().withOperators(logicalOperators),
/// );
/// ```
///
/// The evaluation half is already in place — `defaultCompoundInterpreters`
/// knows `and`, `or`, `nor` and `not` — so this is all that is needed.
///
/// ## Why they are not on by default
///
/// CASL's guide argues that `$and`, `$or` and `$not` are already expressible by
/// combining `can` and `cannot` rules, and that `$nor` is a sign the permission
/// logic wants rethinking. That is a fair argument and the reason the default
/// set matches theirs exactly.
///
/// The reason to switch them on anyway is the other direction: a server that
/// *already* sends `$or` in its rules. Refusing them then means the client and
/// the server disagree about what a rule says, which is worse than either
/// position on whether the operator is good style.
///
/// Whichever you choose, choose it on both sides.
const Map<String, OperatorParser> logicalOperators = {
  r'$and': _and,
  r'$or': _or,
  r'$nor': _nor,
  r'$not': _not,
};

Condition _and(OperatorCall c) => _combine('and', c);
Condition _or(OperatorCall c) => _combine('or', c);
Condition _nor(OperatorCall c) => _combine('nor', c);

/// `$not` is a *field* operator — `{'x': {r'$not': {r'$gt': 5}}}` — where the
/// other three are document ones. It negates the operators written inside it.
Condition _not(OperatorCall c) {
  final query = _asQuery(c.value);
  if (query == null) {
    return c.refuse('expects an object of field operators');
  }

  return CompoundCondition('not', [c.parser.parse(query, field: c.field)]);
}

Condition _combine(String operator, OperatorCall c) {
  final queries = c.value;
  if (queries is! List || queries.isEmpty) {
    return c.refuse('expects a non-empty list of queries');
  }

  final conditions = <Condition>[];
  for (final entry in queries) {
    final query = _asQuery(entry);
    if (query == null) return c.refuse('expects every entry to be a query');
    conditions.add(c.parser.parse(query));
  }

  return CompoundCondition(operator, conditions);
}

/// A nested query, whatever map type it arrived as.
Map<String, Object?>? _asQuery(Object? value) {
  if (value is! Map) return null;

  final query = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) return null;
    query[entry.key! as String] = entry.value;
  }
  return query;
}

Condition _eq(OperatorCall c) => FieldCondition('eq', c.field, c.value);
Condition _ne(OperatorCall c) => FieldCondition('ne', c.field, c.value);

Condition _lt(OperatorCall c) => _ordered('lt', c);
Condition _lte(OperatorCall c) => _ordered('lte', c);
Condition _gt(OperatorCall c) => _ordered('gt', c);
Condition _gte(OperatorCall c) => _ordered('gte', c);

Condition _in(OperatorCall c) => _overList('in', c);
Condition _nin(OperatorCall c) => _overList('nin', c);
Condition _all(OperatorCall c) => _overList('all', c);

Condition _size(OperatorCall c) => c.value is int
    ? FieldCondition('size', c.field, c.value)
    : c.refuse('expects a whole number');

Condition _exists(OperatorCall c) => c.value is bool
    ? FieldCondition('exists', c.field, c.value)
    : c.refuse('expects true or false');

Condition _regex(OperatorCall c) {
  final pattern = _regExp(c);
  return pattern == null
      ? c.refuse('expects a pattern string')
      : FieldCondition('regex', c.field, pattern);
}

/// Parses to nothing: it configures the `$regex` beside it rather than being
/// a test of its own.
Condition _options(OperatorCall c) => Condition.always;

Condition _elemMatch(OperatorCall c) {
  final query = c.value;
  // `Map<String, Object?>` alone would miss the `Map<dynamic, dynamic>` a
  // loosely typed decoder produces, and missing it would refuse a rule that is
  // perfectly well formed.
  if (query is! Map || query.keys.any((key) => key is! String)) {
    return c.refuse('expects a nested query');
  }

  // Operators written directly inside `$elemMatch` describe each *element*
  // rather than a field of it, which is how a list of scalars is matched:
  // `{scores: {$elemMatch: {$gte: 80}}}`.
  return FieldCondition(
    'elemMatch',
    c.field,
    c.parser.parse({
      for (final entry in query.entries) entry.key! as String: entry.value,
    }),
  );
}

Condition _ordered(String operator, OperatorCall c) => switch (c.value) {
  final num v => FieldCondition(operator, c.field, v),
  final String v => FieldCondition(operator, c.field, v),
  final DateTime v => FieldCondition(operator, c.field, v),
  _ => c.refuse('expects something orderable — a number, a string or a date'),
};

Condition _overList(String operator, OperatorCall c) => c.value is List
    ? FieldCondition(operator, c.field, c.value)
    : c.refuse('expects a list');

/// Builds a Dart [RegExp] from Mongo's pattern-and-flags pair.
///
/// Dart has no `x` (extended) mode, so asking for one throws rather than
/// quietly matching something else. A regular expression that silently means
/// something different is exactly the authorisation bug nobody finds.
RegExp? _regExp(OperatorCall c) {
  final pattern = c.value;
  if (pattern is RegExp) return pattern;
  if (pattern is! String) return null;

  final options = c.siblings[r'$options'];
  final flags = options is String ? options : '';
  for (final flag in flags.split('')) {
    // `g`, `y` and `d` are legal in JavaScript and change nothing about a
    // single match — ucast resets `lastIndex` around every test precisely so
    // that `g` is harmless. A rule carrying one is not wrong, it is wearing a
    // flag that has no meaning here, and refusing it would reject a rule its
    // own server evaluates happily.
    if ('gyd'.contains(flag)) continue;

    // Anything else *would* change what the pattern means. A regular
    // expression that quietly matches something different is exactly the
    // authorisation bug nobody finds.
    if (!'imsu'.contains(flag)) {
      throw ConditionFormatException(
        'Dart regular expressions have no "$flag" flag',
        field: c.field,
        operator: r'$options',
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
