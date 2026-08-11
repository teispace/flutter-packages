/// Structural equality for the JSON-shaped values a rule carries.
///
/// Written out rather than taken from `package:collection`, which would be a
/// dependency for twenty lines, and rather than trusting `==`: a Dart `Map`
/// and `List` compare by identity, so two rules decoded from the same payload
/// would not be equal to each other. That surfaces as a cache that never hits,
/// or a router rebuilding on every refresh because permissions "changed".
bool deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;

  if (a is List) {
    if (b is! List || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!deepEquals(a[i], b[i])) return false;
    }
    return true;
  }

  if (a is Map) {
    if (b is! Map || a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !deepEquals(a[key], b[key])) return false;
    }
    return true;
  }

  // Numbers are compared by value across int and double, which Dart already
  // does — worth knowing because JSON has one number type, so a condition
  // written `7` must equal a payload that decoded `7.0`.
  return a == b;
}

/// A hash consistent with [deepEquals].
///
/// Order-sensitive for lists and order-*insensitive* for maps, matching what
/// [deepEquals] considers equal.
int deepHash(Object? value) {
  if (value is List) {
    return Object.hashAll([for (final item in value) deepHash(item)]);
  }

  if (value is Map) {
    return Object.hashAllUnordered([
      for (final entry in value.entries)
        Object.hash(entry.key, deepHash(entry.value)),
    ]);
  }

  return value.hashCode;
}
