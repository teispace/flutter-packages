import 'package:casl/src/raw_rule.dart';

/// One rule in its compact wire form: a JSON array, not an object.
///
/// ```json
/// ["read","Article"]
/// ["read,update","Article",{"authorId":7}]
/// ["delete","Article",0,1,0,"published articles are kept"]
/// ```
typedef PackedRule = List<Object?>;

/// Squeezes rules into the array form CASL.js's `packRules` produces.
///
/// The saving is not the array — it is the *tail*. Every optional slot is
/// dropped from the end while it is empty, so the common rule is two strings
/// instead of six keys and their names. On a real grant, a few hundred rules
/// on every sign-in, that is the difference between a payload someone notices
/// and one nobody does.
///
/// The positions are fixed and must not be reordered: action, subject,
/// conditions, inverted, fields, reason. Anything absent is `0`, because a
/// slot that must hold a place cannot simply be missing.
///
/// [packSubject] converts a subject type on the way out, for a server whose
/// rules name classes rather than strings.
List<PackedRule> packRules(
  List<RawRule> rules, {
  String Function(String subjectType)? packSubject,
}) => [
  for (final rule in rules) _pack(rule, packSubject),
];

/// Reads what [packRules] wrote, or what CASL.js's `packRules` wrote.
///
/// Tolerant of a short array by design — that is the format, not damage.
List<RawRule> unpackRules(
  List<Object?> packed, {
  String Function(String packed)? unpackSubject,
}) {
  // As with `RawRule.fromJson`: a payload that cannot be read is a runtime
  // condition, not a programming error, so it arrives as a `FormatException`
  // whatever went wrong underneath. Catching an `Error` is exactly what the
  // lint warns about and exactly what translating one requires.
  try {
    return [for (final rule in packed) _unpack(rule, unpackSubject)];
    // Translating it, not swallowing it — see the comment above.
    // ignore: avoid_catching_errors
  } on ArgumentError catch (error) {
    throw FormatException('not a packed CASL rule: ${error.message}', packed);
  }
}

PackedRule _pack(RawRule rule, String Function(String)? packSubject) {
  final subjects = packSubject == null
      ? rule.subjects
      : rule.subjects.map(packSubject);

  final packed = <Object?>[
    rule.actions.join(','),
    subjects.join(','),
    if (rule.conditions case final conditions?) conditions else 0,
    if (rule.inverted) 1 else 0,
    if (rule.fields case final fields?) fields.join(',') else 0,
    rule.reason ?? '',
  ];

  // Trailing empties are dropped, which is the whole point of the format. `0`
  // and `''` both count as empty, so a rule with only a reason still carries
  // the two zeroes that hold its place.
  while (packed.isNotEmpty && _isEmpty(packed.last)) {
    packed.removeLast();
  }

  return packed;
}

RawRule _unpack(Object? packed, String Function(String)? unpackSubject) {
  if (packed is! List) {
    throw FormatException('a packed rule must be an array, got $packed');
  }

  Object? at(int index) => index < packed.length ? packed[index] : null;

  final action = at(0);
  if (action is! String || action.isEmpty) {
    throw FormatException('a packed rule must start with an action: $packed');
  }

  final subject = at(1);
  final conditions = at(2);
  final fields = at(4);
  final reason = at(5);

  return RawRule(
    actions: action.split(','),
    subjects: _subjects(subject, unpackSubject),
    conditions: switch (conditions) {
      final Map<String, Object?> map => map,
      // `0` is the placeholder for "none", and so is anything else falsy.
      _ => null,
    },
    inverted: at(3) == 1 || at(3) == true,
    fields: fields is String && fields.isNotEmpty ? fields.split(',') : null,
    reason: reason is String && reason.isNotEmpty ? reason : null,
  );
}

List<String> _subjects(Object? packed, String Function(String)? unpack) {
  if (packed is! String || packed.isEmpty) return const ['all'];
  final subjects = packed.split(',');
  return unpack == null ? subjects : subjects.map(unpack).toList();
}

bool _isEmpty(Object? value) =>
    value == null || value == 0 || value == '' || value == false;
