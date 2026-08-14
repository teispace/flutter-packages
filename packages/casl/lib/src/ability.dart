import 'package:casl/src/matchers.dart';
import 'package:casl/src/raw_rule.dart';
import 'package:casl/src/rule.dart';
import 'package:casl/src/rule_index.dart';

/// What a user may do, and the only thing the rest of an app needs to ask.
///
/// ```dart
/// final ability = Ability([
///   RawRule.of(action: 'read', subject: 'Article'),
///   RawRule.of(action: 'manage', subject: 'Article', inverted: true),
/// ]);
///
/// ability.can('read', 'Article');   // false — the later rule wins
/// ```
///
/// See `AbilityBuilder` for the readable way to write rules by hand.
///
/// It understands no condition language of its own: a rule with `conditions`
/// needs a [ConditionsMatcher], and `createMongoAbility` supplies the one most
/// people want. Without one, such a rule throws when it is compiled rather
/// than silently matching nothing.
///
/// Named as CASL.js v7 names it. Its `PureAbility` from v6 is this class; the
/// old `Ability` that bundled a Mongo matcher is `createMongoAbility` here.
class Ability<A extends String, S extends String> extends RuleIndex<A, S> {
  /// Creates an ability over [rules].
  Ability(
    super.rules, {
    super.conditionsMatcher,
    super.fieldsMatcher,
    super.resolveActions,
    super.detectSubjectType,
    super.anyActionName,
    super.anySubjectTypeName,
  });

  final List<AbilityUpdateListener<A, S>> _onUpdate = [];
  final List<AbilityUpdateListener<A, S>> _onUpdated = [];

  /// Whether [action] is permitted on [subject], optionally for one [field].
  ///
  /// [subject] may be a subject type (`'Article'`), an instance, or an instance
  /// wrapped by [subject] — and the two questions differ. Against a type it
  /// asks "is this ever allowed", which is what a menu item needs; against an
  /// instance it evaluates conditions, which is what a button on a row needs.
  ///
  /// ## Which rule decides
  ///
  /// The **last matching rule declared** — not "any forbidding rule". Rules are
  /// prioritised in reverse, so writing
  ///
  /// ```dart
  /// cannot('read', 'Article');
  /// can('read', 'Article');
  /// ```
  ///
  /// permits reading. This surprises people, and it is deliberate: it makes
  /// rules composable, so a role can be layered on top of a base set and
  /// actually override it.
  bool can(A action, [Object? subject, String? field]) {
    final rule = relevantRuleFor(action, subject, field);
    return rule != null && !rule.inverted;
  }

  /// The opposite of [can], and exactly that — including for a subject type.
  bool cannot(A action, [Object? subject, String? field]) =>
      !can(action, subject, field);

  /// The rule that decides [can], or null when nothing matches at all.
  ///
  /// Nothing matching means "not permitted": an ability grants, so silence is
  /// a refusal. The rule itself is returned rather than a boolean because a
  /// forbidding rule may carry a [Rule.reason], which is the difference between
  /// "you cannot do that" and "you cannot do that while the invoice is locked".
  Rule? relevantRuleFor(A action, [Object? subject, String? field]) {
    final subjectType = detectSubjectType(subject);
    final rules = rulesFor(action, subjectType, field);

    for (final rule in rules) {
      if (rule.matchesConditions(subject)) return rule;
    }

    return null;
  }

  /// Replaces every rule and tells anything listening.
  ///
  /// Both events fire around the change: `update` before, with the old rules
  /// still in force, and `updated` after. A UI wants the second; a cache that
  /// needs to read the outgoing state wants the first.
  ///
  /// Both listener lists are copied before being walked, because a listener is
  /// allowed to unsubscribe — itself or another — while it is being called.
  /// Iterating the live list would throw `ConcurrentModificationError`, and the
  /// case is not exotic: a permission change that tears down a widget disposes
  /// it, and disposal is where an unsubscribe lives.
  ///
  /// Returns itself, as CASL.js's `update` does.
  @override
  Ability<A, S> update(List<RawRule> rules) {
    final event = AbilityUpdate<A, S>(this, rules);
    for (final listener in List.of(_onUpdate)) {
      listener(event);
    }

    super.update(rules);

    for (final listener in List.of(_onUpdated)) {
      listener(event);
    }

    return this;
  }

  /// Listens for rule changes. Returns a function that stops listening.
  ///
  /// ```dart
  /// final off = ability.on('updated', (_) => setState(() {}));
  /// ```
  Unsubscribe on(String event, AbilityUpdateListener<A, S> listener) {
    final listeners = switch (event) {
      'update' => _onUpdate,
      'updated' => _onUpdated,
      _ => throw ArgumentError.value(
        event,
        'event',
        'expected "update" or "updated"',
      ),
    };

    // A cascade would run the removal now rather than when the returned
    // function is called, which is the entire point of returning it.
    // ignore: cascade_invocations
    listeners.add(listener);

    return () => listeners.remove(listener);
  }
}

/// Stops an [Ability.on] listener listening.
///
/// Named because a bare `void Function()` in a field declaration says nothing
/// about what calling it does.
typedef Unsubscribe = void Function();

/// Called when an ability's rules change. See [Ability.on].
typedef AbilityUpdateListener<A extends String, S extends String> =
    void Function(AbilityUpdate<A, S> event);

/// A rule change, as reported to an [Ability.on] listener.
final class AbilityUpdate<A extends String, S extends String> {
  /// Creates the event.
  const AbilityUpdate(this.ability, this.rules);

  /// The ability being changed.
  final Ability<A, S> ability;

  /// The rules it is changing to.
  final List<RawRule> rules;

  /// The ability being changed. The name CASL.js v7 uses.
  ///
  /// Identical to [ability] — v7 renamed the field and deprecated the old
  /// spelling, so both exist here and neither is going anywhere.
  Ability<A, S> get target => ability;
}
