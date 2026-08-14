import 'package:casl/src/conditions/condition.dart';
import 'package:casl/src/conditions/field_reader.dart';
import 'package:casl/src/deep_equals.dart';
import 'package:casl/src/matchers.dart';

/// Orders two values the way the condition operators need them ordered.
///
/// Returns 0 when equal, and otherwise -1 or 1. Values that cannot sensibly be
/// compared — a string against a number — report -1 rather than throwing, which
/// means a badly typed condition denies rather than crashing a screen. CASL.js
/// coerces instead and would permit; the difference is recorded in the README.
/// Only `eq`/`ne` treat 0 as meaningful, so the arbitrary half is never the
/// deciding answer for them.
int caslCompare(Object? a, Object? b) {
  if (a == null && b == null) return 0;
  if (deepEquals(a, b)) return 0;
  if (a is num && b is num) return a.compareTo(b);
  if (a is String && b is String) return a.compareTo(b);
  if (a is DateTime && b is DateTime) return a.compareTo(b);
  if (a is Comparable && b is Comparable && a.runtimeType == b.runtimeType) {
    return a.compareTo(b);
  }
  return -1;
}

/// Equality as JavaScript's `===` decides it, for bug-compatibility with
/// `@casl/ability`.
///
/// The condition engine CASL.js delegates to compares with `===`, so two
/// structurally identical objects or lists are **not** equal to it — which
/// means a rule like `{'tags': ['a', 'b']}` can never match anything there.
/// [deepEquals], the default here, matches by value, which is what MongoDB
/// itself does and what a reader expects.
///
/// Pass this to `createMongoAbility` as `strictJsEquality: true` when a
/// CASL.js server is the authority and you would rather agree with it than be
/// right:
///
/// ```dart
/// createMongoAbility(rules, strictJsEquality: true);
/// ```
///
/// Dates are compared by instant rather than by identity, matching the
/// conversion CASL.js applies before comparing.
bool caslStrictJsEquality(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is DateTime && b is DateTime) return a.isAtSameMomentAs(b);
  // Anything with structure compares by identity, as `===` does. Everything
  // else is a primitive, where `===` and Dart's `==` agree.
  if (a is List || a is Map || b is List || b is Map) return false;
  return a == b;
}

/// How one parsed field operator decides whether a subject satisfies it.
///
/// The third parameter is the interpreter running it, which is where the
/// helpers live — [ConditionInterpreter.valueOf] and friends. Take them rather
/// than reaching for `readPath` directly, so a custom field reader or equality
/// still applies.
typedef FieldInterpreter =
    bool Function(
      FieldCondition node,
      Object? subject,
      ConditionInterpreter interpreter,
    );

/// How one parsed compound operator combines its parts.
typedef CompoundInterpreter =
    bool Function(
      CompoundCondition node,
      Object? subject,
      ConditionInterpreter interpreter,
    );

/// Evaluates a parsed [Condition] against a subject.
///
/// One instance per matcher, holding the reader, the equality and the operator
/// tables — so an application that matches against its own model types, or
/// needs an operator CASL leaves out, configures this once.
///
/// ## Adding an operator
///
/// Two halves, and both are needed: `MongoQueryParser` turns `$name` into a
/// [Condition], and this turns that condition into an answer.
///
/// ```dart
/// bool interpretMod(node, subject, it) {
///   final divisor = (node.value! as List)[0]! as int;
///   final remainder = (node.value! as List)[1]! as int;
///   return it.anyOf(
///     it.valueOf(node, subject),
///     (v) => v is int && v % divisor == remainder,
///   );
/// }
///
/// final matcher = mongoConditionsMatcher(
///   parser: const MongoQueryParser().withOperators({r'$mod': parseMod}),
///   interpreter: const ConditionInterpreter().withOperators(
///     fields: {'mod': interpretMod},
///   ),
/// );
/// ```
///
/// Think first about whether the server sending these rules understands the
/// same operator. A condition one side evaluates differently is worse than one
/// neither does.
final class ConditionInterpreter {
  /// Creates an interpreter.
  const ConditionInterpreter({
    this.read = CaslFields.read,
    this.equals = deepEquals,
    this.fieldOperators = defaultFieldInterpreters,
    this.compoundOperators = defaultCompoundInterpreters,
  });

  /// How one field is read from one object.
  final FieldReader read;

  /// How two values are compared. See [caslStrictJsEquality] for the
  /// alternative to the default.
  final ValueEquality equals;

  /// The field operators, keyed by the condition name — `eq`, not `$eq`.
  ///
  /// `MongoQueryParser` strips the `$` when it parses, so the two tables are
  /// keyed differently on purpose: one holds query syntax, this holds
  /// evaluated operators.
  final Map<String, FieldInterpreter> fieldOperators;

  /// The compound operators — `and`, `or`, `nor`, `not`.
  final Map<String, CompoundInterpreter> compoundOperators;

  /// The same interpreter with [fields] and [compound] added, replacing any of
  /// the same name.
  ConditionInterpreter withOperators({
    Map<String, FieldInterpreter> fields = const {},
    Map<String, CompoundInterpreter> compound = const {},
  }) => ConditionInterpreter(
    read: read,
    equals: equals,
    fieldOperators: {...fieldOperators, ...fields},
    compoundOperators: {...compoundOperators, ...compound},
  );

  /// Whether [subject] satisfies [condition].
  bool interpret(Condition condition, Object? subject) => switch (condition) {
    CompoundCondition(:final operator) =>
      (compoundOperators[operator] ?? _unknownCompound)(
        condition,
        subject,
        this,
      ),
    FieldCondition(:final operator) =>
      (fieldOperators[operator] ?? _unknownField)(condition, subject, this),
  };

  // ---------------------------------------------------------------- helpers
  //
  // Public because a custom operator needs them, and because reaching past
  // them to `readPath` or `==` would quietly ignore a caller's own field
  // reader or equality.

  /// The value [node] is about: the field it names, or the subject itself when
  /// it names none — which is how `$elemMatch` matches a list of scalars.
  ///
  /// A list part-way along the path is flattened, so `comments.author` over a
  /// list of comments reads as a list of authors. That is MongoDB's behaviour
  /// and the reason a condition on it matches if *any* of them does.
  Object? valueOf(FieldCondition node, Object? subject) => node.field == null
      ? subject
      : CaslFields.path(subject, node.field!, read: read);

  /// The object a field's last segment should be read from, and that segment.
  ///
  /// What `$exists` and `$size` need: both ask about the last step itself
  /// rather than about its value, so they need the thing that would carry it.
  (Object?, String) parentOf(FieldCondition node, Object? subject) =>
      CaslFields.parent(subject, node.field!, read: read);

  /// Equality as every operator that compares two values means it.
  ///
  /// A regular expression on **either** side tests the other, which is what
  /// makes `{'t': {r'$in': [RegExp('^ab')]}}` do the useful thing. Everything
  /// else defers to [equals].
  bool matchesValue(Object? a, Object? b) {
    if (a is RegExp) return b is String && a.hasMatch(b);
    if (b is RegExp) return a is String && b.hasMatch(a);
    return equals(a, b);
  }

  /// Whether [items] holds [value], by [matchesValue].
  bool includes(Object? items, Object? value) =>
      items is List && items.any((item) => matchesValue(item, value));

  /// Applies [test] to [value], or to any element when it is a list.
  ///
  /// MongoDB's rule for every comparison operator: a condition on a list field
  /// is satisfied by one matching element.
  bool anyOf(Object? value, bool Function(Object? value) test) =>
      value is List ? value.any(test) : test(value);
}

// --------------------------------------------------------------- the tables

/// The field operators the built-in parser can produce.
///
/// Keyed by condition name rather than query syntax — `eq`, not `$eq`.
const Map<String, FieldInterpreter> defaultFieldInterpreters = {
  'eq': _eq,
  'ne': _ne,
  'lt': _lt,
  'lte': _lte,
  'gt': _gt,
  'gte': _gte,
  'in': _in,
  'nin': _nin,
  'all': _all,
  'size': _size,
  'regex': _regex,
  'exists': _exists,
  'elemMatch': _elemMatch,
};

/// The compound operators.
///
/// `nor` and `not` are here although the default parser cannot produce them:
/// CASL's own guide walks through adding `$nor`, and having the evaluation side
/// already present means that is a one-line parser entry rather than two.
const Map<String, CompoundInterpreter> defaultCompoundInterpreters = {
  'and': _and,
  'or': _or,
  'nor': _nor,
  'not': _not,
};

// ------------------------------------------------------------ compound ops

bool _and(CompoundCondition node, Object? subject, ConditionInterpreter it) =>
    node.conditions.every((c) => it.interpret(c, subject));

bool _or(CompoundCondition node, Object? subject, ConditionInterpreter it) =>
    node.conditions.any((c) => it.interpret(c, subject));

bool _nor(CompoundCondition node, Object? subject, ConditionInterpreter it) =>
    !node.conditions.any((c) => it.interpret(c, subject));

bool _not(CompoundCondition node, Object? subject, ConditionInterpreter it) =>
    !it.interpret(node.conditions.first, subject);

bool _unknownCompound(
  CompoundCondition node,
  Object? subject,
  ConditionInterpreter it,
) => throw UnsupportedError(
  'no interpreter for compound operator "${node.operator}". A parser produced '
  'it, so add the matching entry to ConditionInterpreter.compoundOperators.',
);

// --------------------------------------------------------------- field ops

bool _eq(FieldCondition node, Object? subject, ConditionInterpreter it) {
  if (node.value == null && node.field != null) {
    // Mongo's null is "absent or null", not "equal to null", and the question
    // is about the field's *parent* — see [_matchesNull].
    final (parent, field) = it.parentOf(node, subject);
    return parent is List
        ? parent.any((item) => _matchesNull(item, field, it))
        : _matchesNull(parent, field, it);
  }

  final value = it.valueOf(node, subject);

  // MongoDB's rule that a list matches if it *contains* the value — so
  // `{tags: 'draft'}` matches `{tags: ['draft', 'new']}`. Matching the whole
  // list still works, which is how `{tags: ['a','b']}` is exact.
  if (value is List) {
    return it.equals(value, node.value) || it.includes(value, node.value);
  }

  return it.matchesValue(value, node.value);
}

bool _ne(FieldCondition node, Object? subject, ConditionInterpreter it) =>
    !_eq(node, subject, it);

bool _lt(FieldCondition node, Object? subject, ConditionInterpreter it) =>
    it.anyOf(it.valueOf(node, subject), (v) => caslCompare(v, node.value) < 0);

bool _lte(FieldCondition node, Object? subject, ConditionInterpreter it) =>
    it.anyOf(it.valueOf(node, subject), (v) => caslCompare(v, node.value) <= 0);

bool _gt(FieldCondition node, Object? subject, ConditionInterpreter it) =>
    it.anyOf(it.valueOf(node, subject), (v) => caslCompare(v, node.value) > 0);

bool _gte(FieldCondition node, Object? subject, ConditionInterpreter it) =>
    it.anyOf(it.valueOf(node, subject), (v) => caslCompare(v, node.value) >= 0);

bool _in(FieldCondition node, Object? subject, ConditionInterpreter it) =>
    it.anyOf(it.valueOf(node, subject), (v) => it.includes(node.value, v));

bool _nin(FieldCondition node, Object? subject, ConditionInterpreter it) =>
    !_in(node, subject, it);

bool _all(FieldCondition node, Object? subject, ConditionInterpreter it) {
  final wanted = node.value;
  final value = it.valueOf(node, subject);
  return wanted is List &&
      value is List &&
      wanted.every((want) => it.includes(value, want));
}

bool _regex(FieldCondition node, Object? subject, ConditionInterpreter it) =>
    it.anyOf(
      it.valueOf(node, subject),
      (v) => v is String && (node.value! as RegExp).hasMatch(v),
    );

bool _elemMatch(FieldCondition node, Object? subject, ConditionInterpreter it) {
  final value = it.valueOf(node, subject);
  return value is List &&
      value.any((item) => it.interpret(node.value! as Condition, item));
}

/// The length of the list at a field, which is not the same as the length of
/// everything a path collects.
///
/// A path through a list is normally flattened — `items.tags` over
/// `[{tags: [1, 2]}, {tags: [3]}]` reads as `[1, 2, 3]`, and every comparison
/// operator wants exactly that. `$size` does not: it asks about *one* list, so
/// it reads the last segment from each element separately and matches if any of
/// them has the length asked for.
bool _size(FieldCondition node, Object? subject, ConditionInterpreter it) {
  final wanted = node.value;
  if (node.field == null) return subject is List && subject.length == wanted;

  final (parent, field) = it.parentOf(node, subject);
  bool test(Object? item) {
    final value = CaslFields.path(item, field, read: it.read);
    return value is List && value.length == wanted;
  }

  // A numeric segment indexes rather than maps, so it has already selected one
  // element and there is nothing left to spread over.
  return parent is List && int.tryParse(field) == null
      ? parent.any(test)
      : test(parent);
}

bool _exists(FieldCondition node, Object? subject, ConditionInterpreter it) {
  final wanted = node.value == true;
  if (node.field == null) return (subject != null) == wanted;

  final (parent, field) = it.parentOf(node, subject);
  if (parent is List) {
    return parent.any((item) => CaslFields.has(item, field) == wanted);
  }
  if (parent == null) return !wanted;
  return CaslFields.has(parent, field) == wanted;
}

bool _unknownField(
  FieldCondition node,
  Object? subject,
  ConditionInterpreter it,
) => throw UnsupportedError(
  'no interpreter for field operator "${node.operator}". A parser produced it, '
  'so add the matching entry to ConditionInterpreter.fieldOperators.',
);

/// Whether [candidate] satisfies `{field: null}` — Mongo's "absent, or present
/// and null".
///
/// The subtlety is that it asks about something that *could* have carried the
/// field. A missing or scalar [candidate] has not matched: `{'a.b': null}` does
/// not match `{}`, because there is no `a` there to be missing a `b` from. It
/// does match `{'a': {}}`, where there is.
///
/// Reading it the other way — treating an absent parent as a match — makes a
/// client permit records its CASL.js server refuses, which is the direction
/// that matters.
bool _matchesNull(Object? candidate, String field, ConditionInterpreter it) {
  if (candidate is! Map && candidate is! CaslRecord) return false;
  if (!CaslFields.has(candidate, field)) return true;

  final value = it.read(candidate!, field);
  return value == null || (value is List && value.any((item) => item == null));
}
