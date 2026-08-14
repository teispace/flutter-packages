// Replays the answers `@casl/ability` gave, recorded by `tool/parity`.
//
// This is the contract with CASL.js. A rule computed by a server and evaluated
// here has to mean the same thing, and this is what makes that a build failure
// rather than a support ticket.
//
// A failing case means one of three things, and saying which is the work:
//
//   * we are wrong — fix `casl`; the fixture already holds the right answer;
//   * we are deliberately different — mark it `deviates` in `cases.mjs`, with a
//     reason, and add the row to `docs/PARITY.md`;
//   * we are wrong and it is not fixed yet — mark it `pending` with the finding
//     id it is tracked under.
//
// Regenerate with `cd tool/parity && npm run generate`.
@Tags(['parity'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:casl/casl.dart';
import 'package:casl/src/deep_equals.dart';
import 'package:test/test.dart';

void main() {
  final fixture =
      jsonDecode(File('test/fixtures/parity.json').readAsStringSync())
          as Map<String, Object?>;

  final cases = (fixture['cases']! as List).cast<Map<String, Object?>>();

  group('parity with ${fixture['reference']}', () {
    test('the fixture is present and populated', () {
      expect(
        cases,
        isNotEmpty,
        reason: 'run `cd tool/parity && npm run generate`',
      );
    });

    for (final testCase in cases) {
      final id = testCase['id']! as String;
      final deviation = testCase['deviates'] as Map<String, Object?>?;
      final pending = testCase['pending'] as String?;

      test(id, () {
        final expectedByCasl = testCase['expected'];
        final actual = _run(testCase);

        // A known divergence we have not fixed yet, tracked against a finding
        // in docs/PARITY.md. Asserting that it is *still* divergent looks
        // backwards, and is the point: the day somebody fixes it, this fails
        // and tells them to clear the marker. A plain skip would let the
        // bookkeeping rot instead.
        if (pending != null) {
          expect(
            deepEquals(actual, expectedByCasl),
            isFalse,
            reason:
                '$id now agrees with CASL.js — $pending looks fixed.\n'
                'Remove `pending` from tool/parity/cases.mjs and regenerate.',
          );
          return;
        }

        // A deviation with no reason is a decision nobody recorded, which is
        // the one thing this file exists to prevent.
        if (deviation != null) {
          expect(
            deviation['reason'],
            isA<String>(),
            reason: '$id is marked as a deviation but gives no reason',
          );
        }

        final expected = deviation != null ? deviation['dart'] : expectedByCasl;

        expect(
          deepEquals(actual, expected),
          isTrue,
          reason: deviation != null
              ? 'deliberate deviation from CASL.js: ${deviation['reason']}\n'
                    '  expected (ours) $expected\n'
                    '  actually got    $actual'
              : 'CASL.js answers $expected; we answer $actual',
        );
      });
    }
  });
}

/// Runs one case, mirroring `tool/parity/generate.mjs` operation for operation.
Object? _run(Map<String, Object?> testCase) {
  try {
    final rules = [
      for (final rule in testCase['rules']! as List)
        RawRule.fromJson(_decode(rule)! as Map<String, Object?>),
    ];

    // Built inside the try because an unsupported operator throws at
    // construction rather than at check time — which is itself a recorded
    // behaviour, not a harness failure.
    //
    // `strict` and `deny` cases turn on one of the two escape hatches and are
    // then expected to agree with CASL.js *exactly*. That is what makes each of
    // them a tested behaviour rather than a claim in a doc comment.
    Ability ability() => createMongoAbility(
      rules,
      strictJsEquality: testCase['strict'] == true,
      onUnparsableCondition: testCase['deny'] == true
          ? UnparsableCondition.deny
          : UnparsableCondition.fail,
    );

    return switch (testCase['op']) {
      'can' => _can(testCase, ability()),
      'rules' =>
        ability()
            .possibleRulesFor(
              testCase['action']! as String,
              testCase['subjectType'] as String?,
            )
            .length,
      'actions' =>
        ability().actionsFor(testCase['subjectType']! as String).toList()
          ..sort(),
      'ast' => _canonicalAst(
        rulesToAst(
          ability(),
          testCase['action']! as String,
          testCase['subjectType']! as String,
        ),
      ),
      'defaults' => rulesToFields(
        ability(),
        testCase['action']! as String,
        testCase['subjectType']! as String,
      ),
      'fields' => permittedFieldsOf(
        ability(),
        testCase['action']! as String,
        _subject(testCase['subject']),
        allFields: (testCase['allFields']! as List).cast<String>(),
      ),
      'pack' => packRules(rules),
      final other => throw StateError('unknown op "$other"'),
    };
  } on Object {
    return const {'!throws': true};
  }
}

bool _can(Map<String, Object?> testCase, Ability ability) {
  final check = testCase['check']! as Map<String, Object?>;
  return ability.can(
    check['action']! as String,
    _subject(check['subject']),
    check['field'] as String?,
  );
}

/// A case's subject: either a bare type, or `{type, value}` for an instance.
Object? _subject(Object? spec) => switch (spec) {
  null => null,
  final String type => type,
  final Map<String, Object?> instance => subject(
    instance['type']! as String,
    _decode(instance['value']),
  ),
  _ => throw StateError('unreadable subject $spec'),
};

/// Turns the JSON-safe markers from `cases.mjs` back into real values.
Object? _decode(Object? value) => switch (value) {
  final Map<String, Object?> map when map.containsKey('!re') => RegExp(
    map['!re']! as String,
    caseSensitive: !(map['flags']! as String).contains('i'),
    multiLine: (map['flags']! as String).contains('m'),
    dotAll: (map['flags']! as String).contains('s'),
    unicode: (map['flags']! as String).contains('u'),
  ),
  final Map<String, Object?> map when map.containsKey('!date') =>
    DateTime.parse(map['!date']! as String),
  final Map<String, Object?> map => {
    for (final entry in map.entries) entry.key: _decode(entry.value),
  },
  final List<Object?> list => [for (final item in list) _decode(item)],
  _ => value,
};

/// The shape `generate.mjs` writes, so the two can be compared directly.
Object? _canonicalAst(Condition? condition) => switch (condition) {
  null => null,
  FieldCondition(:final operator, :final field, :final value) => {
    'op': operator,
    'field': field,
    'value': value is Condition ? _canonicalAst(value) : _encode(value),
  },
  CompoundCondition(:final operator, :final conditions) => {
    'op': operator,
    'children': [for (final child in conditions) _canonicalAst(child)],
  },
};

/// The inverse of [_decode], for values that reach the recorded output.
Object? _encode(Object? value) => switch (value) {
  // Flag order matches JavaScript's `RegExp.flags`, which is fixed.
  final RegExp re => {
    '!re': re.pattern,
    'flags': [
      if (!re.isCaseSensitive) 'i',
      if (re.isMultiLine) 'm',
      if (re.isDotAll) 's',
      if (re.isUnicode) 'u',
    ].join(),
  },
  final DateTime date => {'!date': date.toUtc().toIso8601String()},
  final Map<String, Object?> map => {
    for (final entry in map.entries) entry.key: _encode(entry.value),
  },
  final List<Object?> list => [for (final item in list) _encode(item)],
  _ => value,
};
