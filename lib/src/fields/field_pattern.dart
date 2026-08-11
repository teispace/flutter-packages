import 'package:casl/src/matchers.dart';

/// Characters that mean something to a regular expression and must not.
final _special = RegExp(r'[-/\\^$+?.()|[\]{}]');

/// A dot, some stars, a dot — the whole of the wildcard syntax.
final _wildcard = RegExp(r'\.?\*+\.?');

/// The first run of stars inside one wildcard.
final _stars = RegExp(r'\*+');

/// Matches a field name against patterns, with `*` and `**`.
///
/// | Pattern | Matches | Does not match |
/// |---|---|---|
/// | `title` | `title` | `titles` |
/// | `address.*` | `address`, `address.city` | `address.geo.lat` |
/// | `address.**` | `address`, `address.city`, `address.geo.lat` | `title` |
/// | `*` | `title` | `address.city` |
/// | `**` | anything | — |
///
/// `*` stops at a dot and `**` crosses them, which is the same distinction
/// `.gitignore` and shell globs make. Note that `address.*` also matches
/// `address` itself: a rule about the parts of a thing is taken to be a rule
/// about the thing.
///
/// The pattern is compiled once per rule, on the first field asked about, and
/// a set of patterns with no star at all skips regular expressions entirely.
bool Function(String field) fieldPatternMatcher(List<String> fields) {
  RegExp? pattern;
  var compiled = false;

  return (field) {
    if (!compiled) {
      compiled = true;
      // The common case by a wide margin: an explicit list of field names. A
      // regular expression would give the same answer more slowly.
      pattern = fields.every((f) => !f.contains('*'))
          ? null
          : _createPattern(fields);
    }

    final regexp = pattern;
    return regexp == null ? fields.contains(field) : regexp.hasMatch(field);
  };
}

/// The default [FieldsMatcher] — [fieldPatternMatcher].
const FieldsMatcher defaultFieldsMatcher = fieldPatternMatcher;

RegExp _createPattern(List<String> fields) {
  final patterns = fields.map(_toPattern);
  final joined = fields.length > 1
      ? '(?:${patterns.join('|')})'
      : patterns.first;

  return RegExp('^$joined\$');
}

String _toPattern(String field) {
  // Two passes, and the order matters. The first escapes everything a regular
  // expression would misread — except a dot next to a star, which the second
  // pass needs to see in order to tell `a.*` from `a\.*`.
  final escaped = field.replaceAllMapped(_special, (match) {
    final text = match[0]!;
    if (text == '.' && _isNextToStar(field, match.start)) return text;
    return '\\$text';
  });

  return escaped.replaceAllMapped(_wildcard, (match) {
    final text = match[0]!;

    // `+` when the wildcard must consume something: a leading `*` is the whole
    // name, and a wildcard fenced by dots is a whole segment. Otherwise `*`,
    // so `address.*` can also match `address`.
    final quantifier =
        escaped.startsWith('*') || (text.startsWith('.') && text.endsWith('.'))
        ? '+'
        : '*';

    // One star stays inside a segment; two cross them.
    final atom = text.contains('**') ? '.' : '[^.]';
    final body = text
        .replaceAll('.', r'\.')
        .replaceFirst(_stars, '$atom$quantifier');

    // A trailing wildcard is optional, which is what lets `address.*` match a
    // bare `address` — the field with no parts named.
    return match.start + text.length == escaped.length ? '(?:$body)?' : body;
  });
}

bool _isNextToStar(String field, int index) =>
    (index > 0 && field[index - 1] == '*') ||
    (index + 1 < field.length && field[index + 1] == '*');
