import 'package:casl/src/ability.dart';
import 'package:casl/src/fields/field_pattern.dart';

/// Which fields of [subject] may be touched by [action].
///
/// The question a form asks: not "may I edit this invoice" but "which of its
/// boxes do I render". Answering it rule by rule at each field would give the
/// wrong answer, because a later rule can take a field back.
///
/// ```dart
/// permittedFieldsOf(
///   ability,
///   'update',
///   article,
///   allFields: ['title', 'body', 'published'],
/// );
/// ```
///
/// [allFields] is required and cannot be inferred: a rule with no `fields`
/// means *every* field, and only the caller knows what a subject's fields are.
/// Dart has no runtime reflection to fall back on, and generating the list
/// would tie it to your class's identifiers rather than to the names the
/// server writes rules about.
///
/// Rules are applied lowest priority first so the last one written wins — the
/// same precedence as [Ability.can], applied per field: a rule that
/// permits adds its fields, one that forbids removes them.
List<String> permittedFieldsOf<A extends String, S extends String>(
  Ability<A, S> ability,
  A action,
  Object? subject, {
  required List<String> allFields,
}) {
  final subjectType = ability.detectSubjectType(subject);
  final rules = ability.possibleRulesFor(action, subjectType);
  final permitted = <String>{};

  // Backwards: `possibleRulesFor` is highest-priority first, and the rule that
  // decides has to be applied last.
  for (final rule in rules.reversed) {
    if (!rule.matchesConditions(subject)) continue;

    final fields = rule.origin.fields ?? allFields;
    if (rule.inverted) {
      permitted.removeAll(_expand(fields, allFields));
    } else {
      permitted.addAll(_expand(fields, allFields));
    }
  }

  // Ordered as the caller listed them, not as the rules happened to mention
  // them: this drives a form, and a form's field order is a design decision.
  return [
    for (final field in allFields)
      if (permitted.contains(field)) field,
  ];
}

/// Which fields of a subject may be touched, asked over and over.
///
/// [permittedFieldsOf] needs the subject's whole field list on every call,
/// which is fine once and tedious in a repository that asks per row. This holds
/// the ability, the action and a way to find a type's fields, so the call site
/// is left with the interesting part:
///
/// ```dart
/// final readable = AccessibleFields(
///   ability,
///   'read',
///   allFieldsOf: (type) => schema[type]!,
/// );
///
/// readable.ofType('Article');   // every article's readable fields
/// readable.of(article);         // this article's, conditions evaluated
/// ```
///
/// The counterpart of CASL.js's class of the same name. The two questions
/// differ in the same way `can` does: against a type it asks "which fields are
/// ever readable", against an instance it evaluates conditions.
final class AccessibleFields<A extends String, S extends String> {
  /// Reads [action] fields out of abilities, finding each type's fields with
  /// [allFieldsOf].
  const AccessibleFields(
    this.ability,
    this.action, {
    required this.allFieldsOf,
  });

  /// The ability being asked.
  final Ability<A, S> ability;

  /// The action every question is about.
  final A action;

  /// Every field a subject type has.
  ///
  /// Required for the same reason [permittedFieldsOf] requires `allFields`: a
  /// rule with no `fields` means *all* of them, and only the caller knows what
  /// a subject's fields are.
  final List<String> Function(S subjectType) allFieldsOf;

  /// The fields readable on *any* subject of [subjectType].
  List<String> ofType(S subjectType) => permittedFieldsOf(
    ability,
    action,
    subjectType,
    allFields: allFieldsOf(subjectType),
  );

  /// The fields readable on this one [subject], with conditions evaluated.
  List<String> of(Object? subject) => permittedFieldsOf(
    ability,
    action,
    subject,
    allFields: allFieldsOf(ability.detectSubjectType(subject)),
  );
}

/// Turns a rule's patterns back into concrete field names.
///
/// A rule may say `address.*`; a form needs `address.city`. Resolving against
/// [allFields] is the only way round, since a pattern describes a set rather
/// than listing one.
Set<String> _expand(List<String> patterns, List<String> allFields) {
  if (patterns.every((p) => !p.contains('*'))) return patterns.toSet();

  final matches = fieldPatternMatcher(patterns);
  return {
    for (final field in allFields)
      if (matches(field)) field,
  };
}

/// The values a new subject must have for [action] to be permitted on it.
///
/// Turns the conditions of the permitting rules into a starting object — so a
/// user who may only create articles with `status: 'draft'` gets a form that
/// already says draft, rather than one that lets them choose and then refuses.
///
/// ```dart
/// rulesToFields(ability, 'create', 'Article');   // {'status': 'draft'}
/// ```
///
/// Only plain values are taken. A condition like `{views: {$gte: 100}}`
/// describes a range rather than a value, and inventing one would be a guess
/// presented to the user as a fact. Forbidding rules are skipped for the same
/// reason: they say what is *not* allowed, which is not a default.
Map<String, Object?> rulesToFields<A extends String, S extends String>(
  Ability<A, S> ability,
  A action,
  S subjectType,
) {
  final fields = <String, Object?>{};

  for (final rule in ability.rulesFor(action, subjectType)) {
    final conditions = rule.origin.conditions;
    if (rule.inverted || conditions == null) continue;

    for (final entry in conditions.entries) {
      // A nested map is an operator query, not a value.
      if (entry.value is Map) continue;
      _setByPath(fields, entry.key, entry.value);
    }
  }

  return fields;
}

/// Writes [value] at a dotted [path], creating the maps on the way.
void _setByPath(Map<String, Object?> target, String path, Object? value) {
  if (!path.contains('.')) {
    target[path] = value;
    return;
  }

  final segments = path.split('.');
  var current = target;
  for (var i = 0; i < segments.length - 1; i++) {
    final next = current[segments[i]];
    if (next is Map<String, Object?>) {
      current = next;
    } else {
      current = current[segments[i]] = <String, Object?>{};
    }
  }

  current[segments.last] = value;
}
