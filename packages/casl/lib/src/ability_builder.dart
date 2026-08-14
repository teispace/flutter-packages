import 'package:casl/src/ability.dart';
import 'package:casl/src/conditions/mongo_matcher.dart';
import 'package:casl/src/raw_rule.dart';

/// Builds the ability an [AbilityBuilder] has collected rules for.
///
/// `createMongoAbility` is one, and is the default. Anything with the same
/// shape works — a subclass, or a bare [Ability] with your own matcher.
typedef AbilityFactory<A extends String, S extends String> =
    Ability<A, S> Function(List<RawRule> rules);

/// Writes one rule. [AbilityBuilder.can] and [AbilityBuilder.cannot] are these.
///
/// Callable, so the common case reads exactly as it does in CASL.js:
///
/// ```dart
/// can('read', 'Article');
/// can.each(['update', 'delete'], 'Article');
/// ```
///
/// CASL.js overloads its first parameter on whether it is given a string or an
/// array. Dart cannot overload, and typing the parameter `Object` to fake it
/// would throw away the thing this generic exists for — so the many-action form
/// is a second entry point rather than a second meaning for the first.
final class RuleAdder<A extends String, S extends String> {
  const RuleAdder._(this._add);

  final RuleRef Function(
    List<String> actions,
    S? subject,
    Map<String, Object?>? conditions,
    Object? fields,
  )
  _add;

  /// Writes a rule about one [action].
  ///
  /// Omitting [subject] writes it about every subject type, which is how a
  /// claim-style ability — `can('read')` with no subjects at all — is
  /// expressed.
  RuleRef call(
    A action, [
    S? subject,
    Map<String, Object?>? conditions,
    Object? fields,
  ]) => _add([action], subject, conditions, fields);

  /// Writes **one** rule covering all of [actions].
  ///
  /// One rule rather than several: it packs smaller, and a query built from it
  /// gets one branch instead of several identical ones.
  ///
  /// ## Why this parameter is `List<String>` and not `List<A>`
  ///
  /// Because `List<A>` is a trap here, and a silent one. When `A` is being
  /// *inferred* — which is every untyped `defineAbility((can, cannot) { … })` —
  /// the lambda's body is analysed before `A` is known, so an inline list
  /// literal in this position reifies as `List<Object?>` and fails the runtime
  /// parameter check. `can.each(['update', 'delete'], 'Article')`, the most
  /// natural way to write the call, would throw at runtime with a message about
  /// a type nobody wrote. A list held in a variable first would work. Silently
  /// depending on that is worse than the typing is worth.
  ///
  /// A `List<A>` still *passes* — `List<AppAction>` is a `List<String>` — so
  /// nothing is lost when you have one. What is lost is the analyser rejecting
  /// a raw `['reed']`, and that only for the many-action form: [call], which is
  /// the overwhelmingly common one, keeps `A`, as does [subject] on both.
  RuleRef each(
    List<String> actions, [
    S? subject,
    Map<String, Object?>? conditions,
    Object? fields,
  ]) => _add(actions, subject, conditions, fields);
}

/// Collects rules in the order they are written, then builds an ability.
///
/// ```dart
/// final builder = AbilityBuilder()
///   ..can('read', 'Article')
///   ..can.each(['update', 'delete'], 'Article', {'authorId': userId})
///   ..cannot('delete', 'Article', {'published': true})
///       .because('a published article cannot be deleted');
///
/// final ability = builder.build();
/// ```
///
/// Conditions and fields are positional, in that order — `can(action, subject,
/// conditions, fields)`. CASL.js overloads its third parameter on the type it
/// is given; Dart does not need to, so the order is fixed and the analyzer
/// checks it. Conditions come first because they are far more common; a rule
/// with fields and no conditions passes `null` for them.
///
/// **Order is meaning.** Rules are checked last-first, so each line overrides
/// the ones above it. Write the broad grant first and narrow it afterwards, the
/// way the example above does — that is the shape that reads correctly.
///
/// See [defineAbility] for the same thing in one expression.
class AbilityBuilder<A extends String, S extends String> {
  /// Starts an empty builder that will [build] with [create].
  ///
  /// Defaults to `createMongoAbility`, which is what almost every caller wants
  /// and what CASL.js's `new AbilityBuilder(createMongoAbility)` gives you.
  /// Pass something else to build a subclass, or a bare [Ability] with your own
  /// conditions matcher:
  ///
  /// ```dart
  /// AbilityBuilder((rules) => Ability(rules, conditionsMatcher: mine));
  /// ```
  AbilityBuilder([AbilityFactory<A, S>? create]) : _create = create {
    can = RuleAdder<A, S>._(
      (actions, subject, conditions, fields) => _add(
        RawRule.of(
          action: actions,
          subject: subject,
          fields: fields,
          conditions: conditions,
        ),
      ),
    );
    cannot = RuleAdder<A, S>._(
      (actions, subject, conditions, fields) => _add(
        RawRule.of(
          action: actions,
          subject: subject,
          fields: fields,
          conditions: conditions,
          inverted: true,
        ),
      ),
    );
  }

  /// Permits an action. See [RuleAdder].
  late final RuleAdder<A, S> can;

  /// Forbids an action. See [RuleAdder].
  ///
  /// Only meaningful *after* something that permits it — a forbidding rule
  /// with nothing to override changes nothing, because the absence of a rule
  /// already refuses.
  late final RuleAdder<A, S> cannot;

  final AbilityFactory<A, S>? _create;
  final List<RawRule> _rules = [];

  /// The rules collected so far, in the order they were written.
  List<RawRule> get rules => List.unmodifiable(_rules);

  /// Builds an ability over everything collected.
  ///
  /// Uses the factory given to the constructor, or [create] to override it for
  /// one call, or `createMongoAbility` when neither says otherwise.
  ///
  /// That default matters: it used to be a bare [Ability], which has no
  /// conditions matcher and therefore threw on any rule carrying conditions.
  /// The failure arrived at `build()` time, from a rule written correctly, with
  /// an error about an option the caller had never heard of.
  Ability<A, S> build({AbilityFactory<A, S>? create}) {
    final factory = create ?? _create;
    return factory != null ? factory(rules) : createMongoAbility<A, S>(rules);
  }

  RuleRef _add(RawRule rule) {
    _rules.add(rule);
    return RuleRef._(_rules, _rules.length - 1);
  }
}

/// A handle on the rule just written, so a reason can be attached to it.
///
/// Returned rather than taken as a parameter because `.because(...)` reads as
/// a sentence, and because a reason is only ever wanted on a small minority of
/// rules — the ones a user will be shown.
final class RuleRef {
  const RuleRef._(this._rules, this._index);

  final List<RawRule> _rules;
  final int _index;

  /// Explains why the rule forbids something.
  ///
  /// Surfaces as `ForbiddenError.message`, so it is user-facing copy: write it
  /// for the person who hit the wall, not for the log.
  ///
  /// Returns itself, matching CASL.js's `RuleBuilder`.
  RuleRef because(String reason) {
    final rule = _rules[_index];
    _rules[_index] = RawRule(
      actions: rule.actions,
      subjects: rule.subjects,
      fields: rule.fields,
      conditions: rule.conditions,
      inverted: rule.inverted,
      reason: reason,
    );

    // Chainable because CASL.js's `RuleBuilder.because` is, so a rule ported
    // from JavaScript keeps compiling. The lint is right in general — a
    // cascade is the Dart way — and wrong here, where the shape is the point.
    // ignore: avoid_returning_this
    return this;
  }
}

/// An ability in one expression, which is how CASL's own documentation writes
/// nearly every example.
///
/// ```dart
/// final ability = defineAbility((can, cannot) {
///   can('read', 'Article');
///   can('update', 'Article', {'authorId': user.id});
///   cannot('delete', 'Article', {'published': true})
///       .because('a published article cannot be deleted');
/// });
/// ```
///
/// The two parameters are [AbilityBuilder.can] and [AbilityBuilder.cannot], so
/// name them whatever reads best where you are — `allow` and `forbid` if `can`
/// next to `ability.can` confuses people, which is a complaint CASL's cookbook
/// takes seriously enough to have a page about. Both carry `.each` for a rule
/// covering several actions.
///
/// [create] chooses what gets built, exactly as [AbilityBuilder.build] does.
/// Use [defineAbilityAsync] when the rules need something awaited.
Ability<A, S> defineAbility<A extends String, S extends String>(
  void Function(RuleAdder<A, S> can, RuleAdder<A, S> cannot) define, {
  AbilityFactory<A, S>? create,
}) {
  final builder = AbilityBuilder<A, S>(create);
  define(builder.can, builder.cannot);
  return builder.build();
}

/// [defineAbility] for rules that need something awaited on the way.
///
/// ```dart
/// final ability = await defineAbilityAsync((can, cannot) async {
///   final settings = await loadWorkspaceSettings();
///   if (settings.readOnly) cannot('manage', 'all');
/// });
/// ```
///
/// Separate rather than an overload because Dart has no overloading, and
/// because a function that sometimes returns a `Future` is worse than two that
/// each return one thing.
Future<Ability<A, S>> defineAbilityAsync<A extends String, S extends String>(
  Future<void> Function(RuleAdder<A, S> can, RuleAdder<A, S> cannot) define, {
  AbilityFactory<A, S>? create,
}) async {
  final builder = AbilityBuilder<A, S>(create);
  await define(builder.can, builder.cannot);
  return builder.build();
}
