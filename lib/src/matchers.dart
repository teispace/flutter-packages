/// The result of compiling one rule's conditions.
///
/// Compiled once and reused, because a rule is checked far more often than it
/// is built — a list screen asks the same question per row.
abstract interface class ConditionsMatch {
  /// Whether [subject] satisfies the conditions.
  ///
  /// [subject] is the unwrapped value, never a `Subject` wrapper.
  bool matches(Object? subject);

  /// Whether these conditions hold for *every* possible subject.
  ///
  /// Almost always false. It matters for one case and one only: an inverted
  /// rule checked against a subject *type* rather than an instance. Asking
  /// "can I read Posts at all?" cannot evaluate `{authorId: 42}`, so a
  /// forbidding rule is only allowed to answer for the whole type when its
  /// conditions restrict nothing.
  bool get matchesEverything;
}

/// Compiles a rule's `conditions` into something that can be asked.
///
/// Pluggable because the condition language is not fixed. The default
/// understands MongoDB-style operators, matching CASL.js; supply your own to
/// add operators, or to match against something other than a map.
typedef ConditionsMatcher =
    ConditionsMatch Function(Map<String, Object?> conditions);

/// Compiles a rule's `fields` into a predicate over one field name.
///
/// Pluggable for the same reason, though the default — `*` within a segment,
/// `**` across segments — is what CASL.js does and what most callers want.
typedef FieldsMatcher =
    bool Function(String field) Function(List<String> fields);
