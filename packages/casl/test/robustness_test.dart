// What happens when a server sends something this build did not expect.
//
// Rules cross a network. They are the one input to this package that is not
// written by the person compiling it, so the boundary that reads them has to
// fail in a way an application can catch and report — never with a `TypeError`
// from four frames down, and never by quietly producing a *different rule*
// from the one that was sent.
import 'dart:convert';
import 'dart:math';

import 'package:casl/casl.dart';
import 'package:test/test.dart';

/// What reading a rule off a network is allowed to throw.
///
/// One type, on purpose. Anything else — a `TypeError`, a `RangeError`, an
/// `ArgumentError` — is either a crash wearing a cast or a claim that the
/// *caller* made a programming mistake, and neither is true of a payload that
/// arrived over HTTP.
final Matcher _named = isA<FormatException>();

void main() {
  group('RawRule.fromJson refuses clearly', () {
    for (final (name, json) in <(String, Map<String, Object?>)>[
      ('no action at all', {'subject': 'Article'}),
      ('a numeric action', {'action': 7}),
      ('a null action', {'action': null}),
      (
        'an action list with a number in it',
        {
          'action': ['read', 7],
        },
      ),
      ('a numeric subject', {'action': 'read', 'subject': 7}),
      (
        'conditions that are a list',
        {
          'action': 'read',
          'subject': 'A',
          'conditions': ['x'],
        },
      ),
      (
        'conditions that are a string',
        {
          'action': 'read',
          'subject': 'A',
          'conditions': 'x',
        },
      ),
      (
        'fields that are a number',
        {
          'action': 'read',
          'subject': 'A',
          'fields': 7,
        },
      ),
      (
        'a reason that is not a string',
        {
          'action': 'read',
          'subject': 'A',
          'reason': 7,
        },
      ),
    ]) {
      test(name, () => expect(() => RawRule.fromJson(json), throwsA(_named)));
    }

    test('and accepts the shapes CASL.js actually emits', () {
      expect(
        RawRule.fromJson(const {'action': 'read', 'subject': 'A'}).actions,
        ['read'],
      );
      expect(
        RawRule.fromJson(const {
          'action': ['read', 'update'],
          'subject': ['A', 'B'],
        }).subjects,
        ['A', 'B'],
      );
      // `actions` rather than `action`, which CASL.js also writes.
      expect(RawRule.fromJson(const {'actions': 'read'}).actions, ['read']);
      // A claim rule: no subject at all.
      expect(RawRule.fromJson(const {'action': 'read'}).subjects, ['all']);
    });
  });

  group('unpackRules refuses clearly', () {
    for (final (name, packed) in <(String, List<Object?>)>[
      ('a rule that is not an array', [42]),
      (
        'a rule that is an object',
        [
          {'action': 'read'},
        ],
      ),
      ('an empty rule', [<Object?>[]]),
      (
        'a rule whose action is not a string',
        [
          [7, 'A'],
        ],
      ),
      (
        'a rule whose action is empty',
        [
          ['', 'A'],
        ],
      ),
      ('a rule that is null', [null]),
    ]) {
      test(name, () => expect(() => unpackRules(packed), throwsA(_named)));
    }

    test('and tolerates a short array, which is the format', () {
      expect(
        unpackRules(const [
          ['read'],
        ]).single.subjects,
        ['all'],
      );
    });
  });

  group('a fuzzed payload never crashes uncatchably', () {
    // Not looking for a specific bug — looking for the *class* of bug where a
    // cast in the reader turns bad input into an error nobody thought to catch.
    test('over 2000 mutated rule objects', () {
      final random = Random(20260814);
      var accepted = 0;
      var refused = 0;

      for (var i = 0; i < 2000; i++) {
        final json = _mutate(random);
        try {
          final rule = RawRule.fromJson(json);
          // Whatever came back must still be a rule, and must survive being
          // written out and read back.
          expect(
            RawRule.fromJson(
              jsonDecode(jsonEncode(rule.toJson())) as Map<String, Object?>,
            ),
            rule,
          );
          accepted++;
        } on FormatException {
          refused++;
        }
      }

      // Both halves matter: refusing everything would pass this test while
      // making the package useless.
      expect(accepted, greaterThan(100), reason: 'nothing was ever accepted');
      expect(refused, greaterThan(100), reason: 'nothing was ever refused');
    });

    test('and neither does building an ability from one', () {
      final random = Random(1);

      for (var i = 0; i < 500; i++) {
        try {
          final ability = createMongoAbility([
            RawRule.fromJson(_mutate(random)),
          ])..validateRules();
          expect(ability.can('read', 'Article'), isA<bool>());
        } on FormatException {
          // The only thing reading a rule is allowed to throw.
        }
      }
    });
  });
}

/// A rule-shaped object with one or two things wrong with it.
Map<String, Object?> _mutate(Random random) {
  final values = <Object?>[
    'read',
    ['read', 'update'],
    7,
    null,
    true,
    <String, Object?>{'authorId': 7},
    <Object?>[],
    <String, Object?>{r'$or': <Object?>[]},
    <String, Object?>{
      'x': {r'$gt': 'not orderable for a date'},
    },
    <String, Object?>{
      'x': {r'$unknown': 1},
    },
    'a' * 300,
    '',
  ];
  Object? pick() => values[random.nextInt(values.length)];

  return {
    if (random.nextBool()) 'action': pick(),
    if (random.nextBool()) 'actions': pick(),
    if (random.nextBool()) 'subject': pick(),
    if (random.nextBool()) 'conditions': pick(),
    if (random.nextBool()) 'fields': pick(),
    if (random.nextBool()) 'inverted': pick(),
    if (random.nextBool()) 'reason': pick(),
  };
}
