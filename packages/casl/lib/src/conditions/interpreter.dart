import 'package:casl/src/conditions/condition.dart';
import 'package:casl/src/conditions/field_reader.dart';
import 'package:casl/src/deep_equals.dart';

/// Orders two values the way the condition operators need them ordered.
///
/// Returns 0 when equal, and otherwise -1 or 1. Values that cannot sensibly be
/// compared — a string against a number — report -1 rather than throwing,
/// which matches CASL.js and means a badly typed condition denies rather than
/// crashing a screen. Only `eq`/`ne` treat 0 as meaningful, so the arbitrary
/// half is never the deciding answer for them.
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

/// Evaluates a parsed [Condition] against a subject.
///
/// One instance per matcher, holding the reader and the operator table, so an
/// application that matches against its own model types configures this once.
final class ConditionInterpreter {
  /// Creates an interpreter.
  const ConditionInterpreter({this.read = readField});

  /// How one field is read from one object.
  final FieldReader read;

  /// Whether [subject] satisfies [condition].
  bool interpret(Condition condition, Object? subject) => switch (condition) {
    CompoundCondition(:final operator, :final conditions) => switch (operator) {
      'and' => conditions.every((c) => interpret(c, subject)),
      'or' => conditions.any((c) => interpret(c, subject)),
      'nor' => !conditions.any((c) => interpret(c, subject)),
      'not' => !interpret(conditions.first, subject),
      _ => throw UnsupportedError('unknown compound operator "$operator"'),
    },
    FieldCondition() => _field(condition, subject),
  };

  bool _field(FieldCondition node, Object? subject) {
    final field = node.field;
    final value = field == null
        ? subject
        : readPath(subject, field, read: read);

    final wanted = node.value;
    return switch (node.operator) {
      'eq' => _eq(node, subject, value),
      'ne' => !_eq(node, subject, value),
      'lt' => _orAny(value, (v) => caslCompare(v, wanted) < 0),
      'lte' => _orAny(value, (v) => caslCompare(v, wanted) <= 0),
      'gt' => _orAny(value, (v) => caslCompare(v, wanted) > 0),
      'gte' => _orAny(value, (v) => caslCompare(v, wanted) >= 0),
      'in' => _orAny(value, (v) => _includes(wanted, v)),
      'nin' => !_orAny(value, (v) => _includes(wanted, v)),
      'all' => _all(wanted, value),
      'size' => value is List && value.length == wanted,
      'regex' => _orAny(
        value,
        (v) => v is String && (node.value! as RegExp).hasMatch(v),
      ),
      'exists' => _exists(node, subject),
      'elemMatch' => _elemMatch(node, value),
      _ => throw UnsupportedError('unknown field operator "${node.operator}"'),
    };
  }

  /// Equality, with MongoDB's rule that a list matches if it *contains* the
  /// value — so `{tags: 'draft'}` matches `{tags: ['draft', 'new']}`. Matching
  /// the whole list still works, which is how `{tags: ['a','b']}` is exact.
  bool _eq(FieldCondition node, Object? subject, Object? value) {
    if (node.value == null && node.field != null) {
      // Mongo's null is "absent or null", not "equal to null".
      final (parent, field) = readParent(subject, node.field!, read: read);
      if (parent is List) {
        return parent.any((item) {
          if (item == null) return true;
          if (!hasField(item, field)) return true;
          return read(item as Object, field) == null;
        });
      }
      return parent == null || !hasField(parent, field) || value == null;
    }

    if (value is List) {
      return deepEquals(value, node.value) || _includes(value, node.value);
    }

    if (node.value is RegExp) {
      return value is String && (node.value! as RegExp).hasMatch(value);
    }

    return deepEquals(value, node.value);
  }

  bool _exists(FieldCondition node, Object? subject) {
    final wanted = node.value == true;
    if (node.field == null) return (subject != null) == wanted;

    final (parent, field) = readParent(subject, node.field!, read: read);
    if (parent is List) {
      return parent.any((item) => hasField(item, field) == wanted);
    }
    if (parent == null) return !wanted;
    return hasField(parent, field) == wanted;
  }

  bool _elemMatch(FieldCondition node, Object? value) =>
      value is List &&
      value.any((item) => interpret(node.value! as Condition, item));

  static bool _all(Object? wanted, Object? value) =>
      wanted is List &&
      value is List &&
      wanted.every((want) => _includes(value, want));

  /// Applies [test] to the value, or to any element when it is a list.
  ///
  /// MongoDB's rule for every comparison operator: a condition on a list field
  /// is satisfied by one matching element.
  static bool _orAny(Object? value, bool Function(Object? value) test) =>
      value is List ? value.any(test) : test(value);

  static bool _includes(Object? items, Object? value) =>
      items is List && items.any((item) => deepEquals(item, value));
}
