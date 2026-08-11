// A worked example: rules arriving from a server, then questions asked of them.
//
// Run with `dart run example/casl_example.dart`.

// An example prints; that is what makes it readable at a glance.
// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:casl/casl.dart';

/// A model that declares its subject type and exposes its fields.
///
/// Declaring the type is what makes this survive `--obfuscate`; see
/// [CaslSubject].
class Article with CaslSubject, CaslRecord {
  Article({required this.id, required this.authorId, this.published = false});

  final int id;
  final int authorId;
  final bool published;

  @override
  String get caslSubjectType => 'Article';

  @override
  Object? caslField(String name) => switch (name) {
    'id' => id,
    'authorId' => authorId,
    'published' => published,
    _ => null,
  };
}

/// Every box the article form can draw. `permittedFieldsOf` narrows it.
const _formFields = ['title', 'body', 'published', 'authorId'];

void main() {
  // What a CASL.js server sends: rules packed as arrays with the empty tail
  // dropped. Pasted verbatim rather than hand-written, because that is the
  // whole point — both halves read the same bytes.
  const payload = '''
[["read","Article"],
 ["update","Article",{"authorId":7},0,"title,body"],
 ["delete","Article",0,1,0,"published articles are kept"]]
''';

  final ability = createMongoAbility(
    unpackRules(jsonDecode(payload) as List<Object?>),
  );

  final mine = Article(id: 1, authorId: 7);
  final theirs = Article(id: 2, authorId: 9);

  print('read any article?      ${ability.can('read', 'Article')}');
  print('update mine?           ${ability.can('update', mine)}');
  print('update theirs?         ${ability.can('update', theirs)}');
  print('delete mine?           ${ability.can('delete', mine)}');

  // A refusal carries the rule's own words, which is what a user should read.
  final refusal = ability.errorUnlessCan('delete', mine);
  print('why not?               ${refusal?.message}');

  // Which fields a form should render, rather than one question per box.
  print(
    'editable fields:       '
    '${permittedFieldsOf(ability, 'update', mine, allFields: _formFields)}',
  );

  // Rules change in place when a role does — no new ability, no new wiring.
  ability.update([RawRule.of(action: 'manage', subject: 'all')]);
  print('after promotion:       ${ability.can('delete', theirs)}');
}
