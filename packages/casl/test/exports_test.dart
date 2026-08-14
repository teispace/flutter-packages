// Asserts that a list of ordinary English words is *not* in your namespace
// after `import 'package:casl/casl.dart'`.
//
// Only the analyzer can check this, so — as with the typed-ability guarantees —
// the test analyses a fixture and reads what it says.
import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('H-01 · the export surface is narrow', () {
    late String output;

    setUpAll(() async {
      final result = await Process.run('dart', [
        'analyze',
        'test/type_safety/exports_are_narrow.dart',
      ]);
      output = '${result.stdout}${result.stderr}';
    });

    // Each of these used to be exported, and each is a word an application
    // might reasonably want for itself.
    for (final (name, replacement) in const [
      ('readField', 'CaslFields.read'),
      ('readPath', 'CaslFields.path'),
      ('readParent', 'CaslFields.parent'),
      ('hasField', 'CaslFields.has'),
      ('alwaysTrue', 'Condition.always'),
      ('alwaysFalse', 'Condition.never'),
      ('oneOrMany', 'RawRule.of'),
      ('subjectValue', 'nothing — internal'),
      ('isSubjectType', 'nothing — internal'),
      ('Subject', 'ForcedSubject'),
    ]) {
      test('$name is gone, replaced by $replacement', () {
        expect(
          output,
          anyOf(
            contains("Undefined name '$name'"),
            contains("The function '$name' isn't defined"),
            contains("The method '$name' isn't defined"),
          ),
          reason: '$name should no longer be exported',
        );
      });
    }
  });
}
