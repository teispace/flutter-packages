import 'package:meta/meta.dart';

/// The subject type that stands for every subject type.
///
/// A rule written about it matches whatever is asked. Configurable per ability
/// because it is a convention rather than a law — `all` is CASL's.
const String anySubjectType = 'all';

/// The action that stands for every action.
///
/// `manage` is CASL's, and it is a convention in exactly the same way.
const String anyAction = 'manage';

/// A type that knows which subject type rules are written about it.
///
/// The recommended way to make your own models checkable:
///
/// ```dart
/// class Article with CaslSubject {
///   Article(this.authorId);
///   final String authorId;
///
///   @override
///   String get caslSubjectType => 'Article';
/// }
///
/// ability.can('update', article);
/// ```
///
/// ## Why this exists, and why guessing the name is not enough
///
/// CASL.js reads `object.constructor.name`. The Dart equivalent is
/// `runtimeType.toString()`, and it is **not safe to rely on**: a release build
/// compiled with `--obfuscate` renames every type, so `Article` becomes
/// something like `a`. Nothing fails — the rule simply stops matching, and the
/// app authorises differently in the build that ships than in the one that was
/// tested.
///
/// Declaring the name makes it survive obfuscation, minification and renaming,
/// because it is a value rather than a symbol. See [subject] for the same
/// guarantee without touching the class.
mixin CaslSubject {
  /// The subject type rules about this object are written against.
  ///
  /// Must match the string used in the rules exactly, and must not be derived
  /// from `runtimeType` — see the mixin's own documentation for why.
  String get caslSubjectType;
}

/// An object paired with the subject type it should be checked as.
///
/// For types you do not own, or plain maps decoded from JSON:
///
/// ```dart
/// final article = subject('Article', {'authorId': userId});
/// ability.can('update', article);
/// ```
///
/// This is the Dart counterpart of CASL.js's `subject()` helper. That one
/// attaches a hidden property to the object; Dart cannot, so the pairing is a
/// wrapper — which has the pleasant side effect of not mutating something you
/// were handed.
@immutable
final class ForcedSubject {
  /// Pairs [value] with its [type].
  const ForcedSubject(this.type, this.value);

  /// The subject type, as written in the rules.
  final String type;

  /// The object itself. Conditions are matched against this, not the wrapper.
  final Object? value;

  @override
  bool operator ==(Object other) =>
      other is ForcedSubject && other.type == type && other.value == value;

  @override
  int get hashCode => Object.hash(type, value);

  @override
  String toString() => 'ForcedSubject($type)';
}

/// Pairs [value] with the subject [type] it should be checked as.
///
/// A function because that is how it reads at the call site, which is the only
/// reason it is not just the constructor.
ForcedSubject subject(String type, Object? value) => ForcedSubject(type, value);

/// Works out which subject type an arbitrary object should be checked as.
///
/// Supplied to an ability to support types that neither use [CaslSubject] nor
/// get wrapped by [subject] — a generated model with a `$type` field, say.
typedef DetectSubjectType = String Function(Object value);

/// Works out the subject type for the objects it recognises, and defers on the
/// rest by returning null.
///
/// The friendlier half of [DetectSubjectType], and what `createMongoAbility`
/// takes. Returning null falls back to [detectSubjectTypeByRuntimeType], so a
/// detector that only knows about your own models does not have to reimplement
/// — or accidentally disable — the handling of [ForcedSubject] and
/// [CaslSubject]:
///
/// ```dart
/// createMongoAbility(
///   rules,
///   detectSubjectType: (value) => value is ApiModel ? value.typeName : null,
/// );
/// ```
typedef PartialDetectSubjectType = String? Function(Object value);

/// The default, in order of how much it can be trusted.
///
/// 1. a [ForcedSubject] wrapper — stated outright,
/// 2. a [CaslSubject] — declared by the type,
/// 3. `runtimeType.toString()` — **a guess**.
///
/// The third is a deliberate last resort and the source of the one bug this
/// library cannot detect for you: it is wrong under `--obfuscate`, silently, in
/// release builds only. Any model that reaches this path should use
/// [CaslSubject] or [subject] instead.
String detectSubjectTypeByRuntimeType(Object value) => switch (value) {
  ForcedSubject(:final type) => type,
  CaslSubject(:final caslSubjectType) => caslSubjectType,
  String() => value,
  _ => value.runtimeType.toString(),
};

/// The object conditions should be matched against.
///
/// Unwraps a [ForcedSubject], because the wrapper carries the type and the
/// value carries the fields.
Object? subjectValue(Object? subject) =>
    subject is ForcedSubject ? subject.value : subject;

/// Whether [value] names a *kind* of thing rather than being one.
///
/// A bare `String` is a subject type. Everything else is an instance, including
/// a [ForcedSubject] wrapper — exactly the distinction that decides whether
/// "can you read a Post?" or "can you read *this* Post?" is being asked.
bool isSubjectType(Object? value) => value is String;
