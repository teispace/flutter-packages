import 'package:meta/meta.dart';

/// A parsed condition, ready to be evaluated.
///
/// Conditions arrive as a MongoDB-shaped map and are parsed once into this
/// tree. Keeping the parsed form separate is what lets a rule be checked
/// thousands of times — once per row of a list — without re-reading the map.
///
/// It is also the extension point: a query builder that turns rules into SQL,
/// or into a Drift `Expression`, walks this rather than the original map.
@immutable
sealed class Condition {
  const Condition();

  /// The condition every subject satisfies.
  ///
  /// What an empty `{}` parses to, and the thing an inverted rule is checked
  /// against when the question is about a subject type rather than an
  /// instance: only a rule that restricts nothing may forbid a whole type.
  static const Condition always = CompoundCondition('and', []);

  /// The condition no subject satisfies.
  ///
  /// An empty `or`, which by the same reasoning as [always] can never be
  /// satisfied: none of nothing holds. It is what a condition the parser cannot
  /// make sense of becomes under `UnparsableCondition.deny` — a rule that
  /// grants nothing rather than a rule that crashes the app.
  static const Condition never = CompoundCondition('or', []);
}

/// A test applied to one field of the subject.
///
/// [field] is a path — `author.id` reads through nested maps, and through
/// lists on the way, so `comments.author` on a list of comments collects every
/// author. `null` means the subject *itself*, which is what `$elemMatch` uses
/// when matching a list of scalars.
@immutable
final class FieldCondition extends Condition {
  /// Creates a field test.
  const FieldCondition(this.operator, this.field, this.value);

  /// Which test — `eq`, `gt`, `in`, and the rest.
  final String operator;

  /// The path to read, or null for the subject itself.
  final String? field;

  /// What to test against. A nested [Condition] for `elemMatch`.
  final Object? value;

  @override
  String toString() => '${field ?? '<itself>'} $operator $value';
}

/// Several conditions combined — `and`, `or`, `nor`, `not`.
@immutable
final class CompoundCondition extends Condition {
  /// Creates a combination.
  const CompoundCondition(this.operator, this.conditions);

  /// How the parts combine.
  final String operator;

  /// The parts.
  final List<Condition> conditions;

  @override
  String toString() => '($operator ${conditions.join(' ')})';
}
