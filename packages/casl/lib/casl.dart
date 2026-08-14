/// Isomorphic authorisation for Dart.
///
/// Define what a user may do as a list of rules, then ask one question
/// everywhere:
///
/// ```dart
/// final ability = (AbilityBuilder()
///       ..can('read', 'Article')
///       ..can('update', 'Article', {'authorId': currentUserId}))
///     .build();
///
/// ability.can('update', article);
/// ```
///
/// The rule format is CASL.js's, so a server running `@casl/ability` can send
/// its rules straight to a Dart client and both will agree about what they
/// mean. That agreement is the point: authorisation duplicated in two languages
/// drifts, and the drift is invisible until somebody sees a button they should
/// not have.
///
/// It is checked rather than asserted. Ninety cases are run through the real
/// `@casl/ability` and replayed here, so a divergence fails a build instead of
/// reaching a user. The handful of places the two deliberately differ are
/// listed in the README, and each one is pinned by a fixture that records the
/// reason.
///
/// ## Two things worth knowing before you start
///
/// **The last matching rule wins.** Not "cannot beats can" — writing `cannot`
/// and then `can` permits. This is what lets rule sets be layered.
///
/// **Declare your subject types.** `runtimeType` is unreliable in obfuscated
/// release builds, so use the `CaslSubject` mixin or the `subject()` helper
/// rather than letting the library guess. See `CaslSubject`.
library;

export 'src/ability.dart';
export 'src/ability_builder.dart';
export 'src/alias.dart';
export 'src/conditions/condition.dart';
export 'src/conditions/field_reader.dart';
export 'src/conditions/interpreter.dart';
export 'src/conditions/mongo_matcher.dart';
export 'src/conditions/mongo_parser.dart';
export 'src/fields/field_pattern.dart';
export 'src/fields/permitted_fields.dart';
export 'src/interop/forbidden_error.dart';
export 'src/interop/pack_rules.dart';
export 'src/matchers.dart';
export 'src/query/rules_to_condition.dart';
// `oneOrMany` normalises the one-or-many shape a rule field can take. It is a
// generic name for an internal chore, and `RawRule.of` is the way to reach it.
export 'src/raw_rule.dart' hide oneOrMany;
export 'src/rule.dart';
export 'src/rule_index.dart';
// `subjectValue` and `isSubjectType` are how `Rule` decides whether it was
// handed a type or an instance. Nothing outside needs them, and both are names
// an application might reasonably want for itself.
export 'src/subject.dart' hide isSubjectType, subjectValue;
