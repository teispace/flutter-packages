import 'package:casl/src/ability.dart';
import 'package:casl/src/conditions/condition.dart';
import 'package:casl/src/rule.dart';

/// How the conditions of one rule become whatever a query builder speaks.
typedef RuleConverter<R> = R Function(Rule rule);

/// How that language combines things.
///
/// Supplied rather than assumed so this works for a `Condition` tree, a Drift
/// `Expression`, a SQL string, or anything else with an *and*, an *or* and a
/// notion of "no restriction".
/// One type parameter rather than CASL.js's two: there, combining produces a
/// different shape from the parts, so the algorithm casts between them. A Dart
/// caller whose finished query is a different type maps it at the end, which
/// costs a line and removes an unchecked cast from the middle of the one
/// function here it would be dangerous in.
final class QueryLanguage<R> {
  /// Describes a target language.
  const QueryLanguage({
    required this.and,
    required this.or,
    required this.not,
    required this.unrestricted,
  });

  /// Everything must hold.
  final R Function(List<R> parts) and;

  /// Any one must hold.
  final R Function(List<R> parts) or;

  /// The negation of one part, for a forbidding rule.
  final R Function(R part) not;

  /// The query that excludes nothing.
  final R Function() unrestricted;
}

/// Turns a grant into a filter: "which records may this user act on".
///
/// The question every list screen has and `can` cannot answer. Asking `can`
/// per row means fetching rows the user may not see and discarding them, which
/// is wrong on a page of ten and impossible on a table of ten million.
///
/// Returns null when **nothing** is permitted — which is not the same as an
/// empty filter, and must not be treated as one. Null means "fetch nothing";
/// an unrestricted result means "fetch everything".
///
/// ```dart
/// final where = rulesToCondition(ability, 'read', 'Article');
/// if (where == null) return const [];        // nothing at all
/// return database.select(where);             // translate and run
/// ```
///
/// ## Why this is not simply "OR the permitting rules together"
///
/// `can` walks rules in priority order and stops at the first match, so a
/// permitting rule is only reached when no higher-priority forbidding rule
/// caught the record first. A query has no such ordering — it is one boolean
/// expression — so that sequence has to be flattened.
///
/// Each permitting rule therefore becomes its own branch of an OR, bounded by
/// the negation of every forbidding rule *above* it. Rules below it are
/// ignored, because reaching it already means they did not apply. Two cases
/// end the walk early: an unconditional `cannot` forbids everything from there
/// down, and an unconditional `can` permits everything from there down.
///
/// Adapted from CASL.js's `rulesToCondition`, and it is subtle enough to be
/// worth reading twice before changing.
R? rulesToCondition<R>(
  List<Rule> rules,
  RuleConverter<R> convert,
  QueryLanguage<R> language,
) {
  final higherCannots = <R>[];
  final branches = <R>[];
  var permitsEverythingBelow = false;

  for (final rule in rules) {
    if (rule.inverted) {
      // An unconditional `cannot` refuses every record a lower-priority rule
      // could have permitted, so nothing below it can contribute.
      if (rule.conditions == null) break;
      higherCannots.add(language.not(convert(rule)));
      continue;
    }

    // An unconditional `can` permits every record not already excluded.
    if (rule.conditions == null) {
      permitsEverythingBelow = true;
      break;
    }

    final branch = convert(rule);
    branches.add(
      higherCannots.isEmpty ? branch : language.and([branch, ...higherCannots]),
    );
  }

  if (permitsEverythingBelow) {
    if (higherCannots.isEmpty) return language.unrestricted();
    if (branches.isEmpty) return language.and(higherCannots);
    branches.add(language.and(higherCannots));
  }

  if (branches.isEmpty) return null;
  return language.or(branches);
}

/// The [Condition] form of [rulesToCondition] — the one most callers want.
///
/// ```dart
/// final where = rulesToAst(ability, 'read', 'Article');
/// ```
///
/// Every rule involved must have parsed conditions, which the built-in Mongo
/// matcher provides. A rule whose matcher cannot produce them throws here
/// rather than being skipped: skipping a *forbidding* rule would widen the
/// query, and a query that returns records the user may not see is the exact
/// failure this function exists to prevent.
Condition? rulesToAst<A extends String, S extends String>(
  Ability<A, S> ability,
  A action,
  S subjectType,
) => rulesToCondition<Condition>(
  ability.rulesFor(action, subjectType),
  _ruleToCondition,
  const QueryLanguage(
    and: _and,
    or: _or,
    not: _not,
    unrestricted: _unrestricted,
  ),
);

Condition _ruleToCondition(Rule rule) {
  final condition = rule.condition;
  if (condition != null) return condition;

  throw StateError(
    'Cannot build a query from rule "${rule.origin}": its conditions were not '
    'parsed. Use createMongoAbility, or a conditions matcher that implements '
    'ParsedConditions.',
  );
}

Condition _and(List<Condition> parts) =>
    parts.length == 1 ? parts.single : CompoundCondition('and', parts);

Condition _or(List<Condition> parts) =>
    parts.length == 1 ? parts.single : CompoundCondition('or', parts);

Condition _not(Condition part) => CompoundCondition('not', [part]);

Condition _unrestricted() => Condition.always;
