/// Isomorphic authorisation for Dart.
///
/// Define what a user may do as a list of rules, then ask one question
/// everywhere:
///
/// ```dart
/// final ability = AbilityBuilder()
///   ..can('read', 'Article')
///   ..can('update', 'Article', {'authorId': currentUserId});
///
/// ability.build().can('update', article);
/// ```
///
/// The rule format is CASL.js's, byte for byte, so a server running
/// `@casl/ability` can send its rules straight to a Dart client and both will
/// agree about what they mean. That agreement is the point: authorisation
/// duplicated in two languages drifts, and the drift is invisible until
/// somebody sees a button they should not have.
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
export 'src/raw_rule.dart';
export 'src/rule.dart';
export 'src/rule_index.dart';
export 'src/subject.dart';
