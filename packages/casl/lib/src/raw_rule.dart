import 'package:casl/src/deep_equals.dart';
import 'package:casl/src/subject.dart';
import 'package:meta/meta.dart';

/// Normalises the one-or-many shape every CASL field accepts.
///
/// `'read'` and `['read', 'update']` are both legal in a rule, in CASL.js and
/// in the JSON a server sends. Dart has no union type, so the value arrives as
/// [Object] and is checked here — once, at the edge, with an error that names
/// what was wrong.
List<String> oneOrMany(Object value, String what) => switch (value) {
  final String single => [single],
  final Iterable<Object?> many => [
    for (final item in many)
      if (item is String)
        item
      else
        throw ArgumentError.value(value, what, 'contains a non-string entry'),
  ],
  _ => throw ArgumentError.value(value, what, 'expected a String or List'),
};

/// One rule, exactly as it travels over the wire.
///
/// The unit a server sends and a client stores. It is data and nothing else —
/// asking it a question is `Rule`'s job, which is compiled from this and caches
/// the matchers a raw rule cannot.
///
/// ```dart
/// const RawRule(actions: ['read'], subjects: ['Article']);
/// RawRule.of(action: 'edit', subject: 'Note', conditions: {'authorId': 7});
/// ```
@immutable
final class RawRule {
  /// Creates a rule from already-normalised lists.
  ///
  /// [RawRule.of] is friendlier for hand-written rules; this one is for code
  /// that already has lists, and for `const`.
  const RawRule({
    required this.actions,
    this.subjects = const [anySubjectType],
    this.fields,
    this.conditions,
    this.inverted = false,
    this.reason,
  });

  /// Creates a rule from values that may each be one item or several.
  factory RawRule.of({
    required Object action,
    Object? subject,
    Object? fields,
    Map<String, Object?>? conditions,
    bool inverted = false,
    String? reason,
  }) => RawRule(
    actions: oneOrMany(action, 'action'),
    subjects: subject == null
        ? const [anySubjectType]
        : oneOrMany(subject, 'subject'),
    // Checked here rather than only when the rule is compiled. An empty list
    // means "no fields at all", which no rule can usefully say — and finding
    // that out at `createMongoAbility` time, several frames from the rule that
    // caused it, is finding out too late. `RawRule.fromJson` turns this into a
    // `FormatException`, because a server sending it is not a programmer
    // mistake. Found by the fuzzer in `test/robustness_test.dart`.
    fields: switch (fields) {
      null => null,
      _ => _nonEmptyFields(oneOrMany(fields, 'fields'), fields),
    },
    conditions: conditions,
    inverted: inverted,
    reason: reason,
  );

  /// Reads a rule from the JSON a CASL.js server sends.
  ///
  /// Accepts both spellings of every one-or-many field, because CASL.js emits
  /// whichever it was given.
  factory RawRule.fromJson(Map<String, Object?> json) {
    final action = json['action'] ?? json['actions'];
    if (action == null) {
      throw const FormatException('a CASL rule must carry an action');
    }

    // Everything in here reports a `FormatException`, including the
    // `ArgumentError`s that `RawRule.of` raises on its own behalf. The
    // distinction matters: an `Error` means "a programmer wrote this wrong",
    // and there is no programmer here — this is a payload off a network, so
    // failing to read it is an ordinary runtime condition an application is
    // expected to catch and report. Catching an `Error` is exactly what the
    // lint warns about and exactly what translating one requires.
    try {
      return RawRule._fromJson(json, action);
      // Translating it, not swallowing it — see the comment above.
      // ignore: avoid_catching_errors
    } on ArgumentError catch (error) {
      throw FormatException('not a CASL rule: ${error.message}', json);
    }
  }

  factory RawRule._fromJson(Map<String, Object?> json, Object action) {
    return RawRule.of(
      action: action,
      subject: json['subject'],
      fields: json['fields'],
      conditions: switch (json['conditions']) {
        final Map<String, Object?> map => map,
        null => null,
        final other => throw FormatException(
          'rule conditions must be an object, got $other',
          json,
        ),
      },
      // Truthy rather than `== true`, and matching `unpackRules`, which has
      // always accepted `1`. A server that writes `"inverted": 1` is not
      // unusual, and reading that as `false` turns a forbidding rule into a
      // permitting one — silently, and in the dangerous direction.
      inverted: json['inverted'] == true || json['inverted'] == 1,
      reason: switch (json['reason']) {
        final String reason => reason,
        null => null,
        // A bare `as String?` here threw a `TypeError`, which is neither
        // catchable-by-contract nor informative. Found by the fuzzer in
        // `test/robustness_test.dart`, which is why that test exists.
        final other => throw FormatException(
          'a rule reason must be a string, got $other',
          json,
        ),
      },
    );
  }

  /// What may (or may not) be done.
  final List<String> actions;

  /// What it may be done to. Defaults to [anySubjectType].
  final List<String> subjects;

  /// The fields the rule is limited to, or null for all of them.
  ///
  /// Supports `*` within one segment and `**` across segments, so
  /// `address.*` covers `address.city` but not `address.geo.lat`.
  final List<String>? fields;

  /// Which subjects the rule applies to, as a MongoDB-style query.
  ///
  /// Only meaningful against an *instance*. Asking about a subject type — "can
  /// I update Articles at all?" — cannot evaluate them; see `Rule`.
  final Map<String, Object?>? conditions;

  /// Whether this rule forbids rather than permits.
  ///
  /// Order decides the outcome, not this flag: see `Ability.can`. A
  /// permitting rule declared *after* a forbidding one wins.
  final bool inverted;

  /// Why the rule forbids something, for the message a user reads.
  final String? reason;

  /// The JSON shape CASL.js reads.
  ///
  /// Single-element lists are written out as lists rather than collapsed to a
  /// string. Both are legal, and preserving the shape a rule was built with
  /// would mean carrying it around for no benefit.
  Map<String, Object?> toJson() => {
    'action': actions,
    'subject': subjects,
    if (fields != null) 'fields': fields,
    if (conditions != null) 'conditions': conditions,
    if (inverted) 'inverted': true,
    if (reason != null) 'reason': reason,
  };

  @override
  bool operator ==(Object other) =>
      other is RawRule &&
      _sameList(other.actions, actions) &&
      _sameList(other.subjects, subjects) &&
      _sameList(other.fields, fields) &&
      deepEquals(other.conditions, conditions) &&
      other.inverted == inverted &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(actions),
    Object.hashAll(subjects),
    fields == null ? null : Object.hashAll(fields!),
    deepHash(conditions),
    inverted,
    reason,
  );

  @override
  String toString() {
    final verb = inverted ? 'cannot' : 'can';
    return '$verb ${actions.join(',')} ${subjects.join(',')}'
        '${fields == null ? '' : ' fields:${fields!.join(',')}'}'
        '${conditions == null ? '' : ' where $conditions'}';
  }

  static List<String> _nonEmptyFields(List<String> fields, Object given) =>
      fields.isNotEmpty
      ? fields
      : throw ArgumentError.value(
          given,
          'fields',
          'cannot be empty — omit it to mean "every field"',
        );

  static bool _sameList(List<String>? a, List<String>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
