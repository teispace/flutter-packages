/// A type whose fields conditions can be matched against.
///
/// Implement it and rules can be checked against your model directly, with no
/// conversion to a map:
///
/// ```dart
/// class Article with CaslSubject, CaslRecord {
///   Article(this.authorId);
///   final String authorId;
///
///   @override
///   String get caslSubjectType => 'Article';
///
///   @override
///   Object? caslField(String name) => switch (name) {
///     'authorId' => authorId,
///     _ => null,
///   };
/// }
/// ```
///
/// Writing the switch by hand is the point. A reflective version would need
/// `dart:mirrors`, which Flutter does not have, or code generation, which would
/// make this package a build-time dependency — and either way the field names
/// would then be tied to your Dart identifiers rather than to the names the
/// server writes rules about.
mixin CaslRecord {
  /// The value of [name], or null when there is no such field.
  ///
  /// Returning null for "absent" and for "present but null" is a genuine
  /// ambiguity, and `$exists` is the one operator that can tell them apart —
  /// override [caslHasField] if your model needs it to.
  Object? caslField(String name);

  /// Whether [name] exists at all, however it is set.
  ///
  /// Defaults to "it exists if it is not null", which is right for most
  /// models and wrong for one that stores a meaningful null.
  bool caslHasField(String name) => caslField(name) != null;
}

/// Reads one field from one object.
///
/// Supplied to the matcher to support shapes the default does not — a
/// generated model with its own accessor, say.
typedef FieldReader = Object? Function(Object target, String field);

/// Reading values out of a subject, the way conditions need them read.
///
/// A namespace rather than four top-level functions, because `readField`,
/// `readPath` and `hasField` are names an application is quite likely to have
/// its own versions of — and a package that forces `hide` clauses on a common
/// import is a package people put down.
///
/// A custom operator should prefer `ConditionInterpreter.valueOf` and its
/// neighbours, which route through whatever [FieldReader] the caller
/// configured. These are the layer underneath.
abstract final class CaslFields {
  /// Reads a field from a [Map] or a [CaslRecord].
  ///
  /// Anything else reads as null, which is the same answer as a missing field.
  /// That is deliberate: a rule about `authorId` checked against something with
  /// no such notion has not matched, and throwing would turn a permission check
  /// into a crash on a screen the user is already looking at.
  static Object? read(Object target, String field) => switch (target) {
    final Map<Object?, Object?> map => map[field],
    final CaslRecord record => record.caslField(field),
    _ => null,
  };

  /// Whether [target] has [field] at all, as `\$exists` means it.
  static bool has(Object? target, String field) => switch (target) {
    final Map<Object?, Object?> map => map.containsKey(field),
    final CaslRecord record => record.caslHasField(field),
    _ => false,
  };

  /// Reads [path] out of [target], following dots and flattening lists.
  ///
  /// See the library documentation on [path] for what a list part-way along
  /// does.
  static Object? path(
    Object? target,
    String path, {
    FieldReader read = CaslFields.read,
  }) => _readPath(target, path, read: read);

  /// The object a path's last segment should be read from, and that segment.
  ///
  /// `\$exists` and null-equality need the *parent*, because both are questions
  /// about whether the last step is there at all rather than about its value.
  static (Object?, String) parent(
    Object? target,
    String path, {
    FieldReader read = CaslFields.read,
  }) => _readParent(target, path, read: read);
}

/// Reads [path] out of [target], following dots and flattening lists.
///
/// ## Lists on the way through
///
/// A list in the middle of a path is mapped over rather than indexed, and the
/// results are flattened — so `comments.author` on
/// `{comments: [{author: 'a'}, {author: 'b'}]}` reads as `['a', 'b']`, and a
/// condition on it matches if *any* of them does. This is MongoDB's behaviour,
/// and it is the reason `{'comments.author': 'a'}` does the useful thing.
///
/// A numeric segment indexes instead, so `comments.0.author` is one comment.
Object? _readPath(
  Object? target,
  String path, {
  FieldReader read = CaslFields.read,
}) {
  if (target == null) return null;
  if (!path.contains('.')) return _readSegment(target, path, read);

  Object? value = target;
  final segments = path.split('.');
  for (var i = 0; i < segments.length; i++) {
    value = _readSegment(value, segments[i], read);
    if (value == null) return null;
    // A scalar part-way through a path means the path is wrong for this
    // object — unless we have arrived, in which case it is the answer.
    if (value is! Map && value is! List && value is! CaslRecord) {
      return i == segments.length - 1 ? value : null;
    }
  }

  return value;
}

(Object?, String) _readParent(
  Object? target,
  String path, {
  FieldReader read = CaslFields.read,
}) {
  final dot = path.lastIndexOf('.');
  if (dot == -1) return (target, path);

  return (
    _readPath(target, path.substring(0, dot), read: read),
    path.substring(dot + 1),
  );
}

Object? _readSegment(Object? target, String segment, FieldReader read) {
  if (target == null) return null;

  if (target is List) {
    final index = int.tryParse(segment);
    if (index != null) {
      return index >= 0 && index < target.length ? target[index] : null;
    }

    // Flattened, not nested: a condition asks about the values, not about the
    // shape of the collection they were found in.
    final collected = <Object?>[];
    for (final item in target) {
      if (item == null) continue;

      final value = _readSegment(item, segment, read);

      // A null here means one of two things, and JavaScript can tell them
      // apart where Dart cannot: `undefined` for a field that is not there,
      // `null` for one that is there and empty. CASL.js drops only the first.
      //
      // That distinction matters more than it looks: JSON has no `undefined`,
      // so *every* null a server sends is the second kind, and dropping them
      // would silently change what `{'items.v': {r'$in': [null]}}` matches.
      if (value == null && !CaslFields.has(item, segment)) continue;

      if (value is List) {
        collected.addAll(value);
      } else {
        collected.add(value);
      }
    }
    return collected;
  }

  return read(target, segment);
}
