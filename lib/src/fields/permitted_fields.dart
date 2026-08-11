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
List<String> permittedFieldsOf(
  Ability ability,
  String action,
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
Map<String, Object?> rulesToFields(
  Ability ability,
  String action,
  String subjectType,
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
