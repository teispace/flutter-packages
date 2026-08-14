// Everything here is written as a *consumer* of the package: one import, no
// reaching into `src/`. If any of it needed a private member, the extension
// point would not really exist.
import 'dart:convert';

import 'package:casl/casl.dart';
import 'package:test/test.dart';

void main() {
  group('G-03 · a custom operator, in about twenty lines', () {
    // `$mod` is in MongoDB and in ucast, and deliberately not in CASL's
    // default set. Adding it takes two halves: parse `$mod` into a condition,
    // then evaluate that condition.
    Condition parseMod(OperatorCall call) {
      final value = call.value;
      return value is List && value.length == 2 && value.every((v) => v is int)
          ? FieldCondition('mod', call.field, value)
          : call.refuse('expects a list of two whole numbers');
    }

    bool interpretMod(
      FieldCondition node,
      Object? subject,
      ConditionInterpreter it,
    ) {
      final [divisor as int, remainder as int] = node.value! as List;
      return it.anyOf(
        it.valueOf(node, subject),
        (v) => v is int && v % divisor == remainder,
      );
    }

    Ability abilityWithMod(Map<String, Object?> conditions) =>
        createMongoAbility(
          [RawRule.of(action: 'read', subject: 'A', conditions: conditions)],
          parser: const MongoQueryParser().withOperators({r'$mod': parseMod}),
          interpreter: const ConditionInterpreter().withOperators(
            fields: {'mod': interpretMod},
          ),
        );

    test('evaluates', () {
      final ability = abilityWithMod({
        'n': {
          r'$mod': [2, 0],
        },
      });

      expect(ability.can('read', subject('A', const {'n': 4})), isTrue);
      expect(ability.can('read', subject('A', const {'n': 5})), isFalse);
    });

    test('spreads over a list field, as the built-in operators do', () {
      final ability = abilityWithMod({
        'ns': {
          r'$mod': [3, 1],
        },
      });

      expect(
        ability.can(
          'read',
          subject('A', const {
            'ns': [2, 4],
          }),
        ),
        isTrue,
        reason: '4 % 3 == 1',
      );
      expect(
        ability.can(
          'read',
          subject('A', const {
            'ns': [2, 3],
          }),
        ),
        isFalse,
      );
    });

    test('refuse() honours the parser policy rather than throwing past it', () {
      // Conditions compile lazily, so `validateRules` is what forces the
      // question — see RuleIndex.validateRules for why that matters.
      expect(
        () => abilityWithMod({
          'n': {r'$mod': 'nonsense'},
        }).validateRules(),
        throwsA(isA<ConditionFormatException>()),
      );
    });

    test('the built-in operators still work beside it', () {
      final ability = abilityWithMod({
        'n': {
          r'$mod': [2, 0],
        },
        's': {
          r'$in': ['x', 'y'],
        },
      });

      expect(
        ability.can('read', subject('A', const {'n': 4, 's': 'x'})),
        isTrue,
      );
      expect(
        ability.can('read', subject('A', const {'n': 4, 's': 'z'})),
        isFalse,
      );
    });

    test('withOperators composes rather than replaces', () {
      const parser = MongoQueryParser();
      final extended = parser.withOperators({r'$mod': parseMod}).withOperators({
        r'$mod2': parseMod,
      });

      expect(extended.operators.keys, containsAll([r'$eq', r'$mod', r'$mod2']));
      expect(parser.operators.containsKey(r'$mod'), isFalse);
    });
  });

  group('logicalOperators — the set CASL leaves out', () {
    Ability abilityWith(Map<String, Object?> conditions) => createMongoAbility(
      [RawRule.of(action: 'read', subject: 'A', conditions: conditions)],
      parser: const MongoQueryParser().withOperators(logicalOperators),
    );

    test(r'$or', () {
      final ability = abilityWith({
        r'$or': [
          {'x': 1},
          {'y': 2},
        ],
      });

      expect(ability.can('read', subject('A', const {'x': 1})), isTrue);
      expect(ability.can('read', subject('A', const {'y': 2})), isTrue);
      expect(ability.can('read', subject('A', const {'z': 3})), isFalse);
    });

    test(r'$and', () {
      final ability = abilityWith({
        r'$and': [
          {'x': 1},
          {'y': 2},
        ],
      });

      expect(
        ability.can('read', subject('A', const {'x': 1, 'y': 2})),
        isTrue,
      );
      expect(ability.can('read', subject('A', const {'x': 1})), isFalse);
    });

    test(r'$nor — the one CASL says cannot be expressed any other way', () {
      final ability = abilityWith({
        r'$nor': [
          {'private': true},
          {'authorId': 2},
        ],
      });

      expect(
        ability.can(
          'read',
          subject('A', const {'private': false, 'authorId': 1}),
        ),
        isTrue,
      );
      expect(
        ability.can(
          'read',
          subject('A', const {'private': true, 'authorId': 1}),
        ),
        isFalse,
      );
      expect(
        ability.can(
          'read',
          subject('A', const {'private': false, 'authorId': 2}),
        ),
        isFalse,
      );
    });

    test(r'$not is a field operator, not a document one', () {
      final ability = abilityWith({
        'n': {
          r'$not': {r'$gt': 5},
        },
      });

      expect(ability.can('read', subject('A', const {'n': 3})), isTrue);
      expect(ability.can('read', subject('A', const {'n': 9})), isFalse);
    });

    test('a malformed logical operator is refused, not mis-evaluated', () {
      expect(
        () => abilityWith({r'$or': 'not a list'}).validateRules(),
        throwsA(isA<ConditionFormatException>()),
      );
    });

    test('they stay off unless asked for', () {
      expect(
        () => createMongoAbility([
          RawRule.of(
            action: 'read',
            subject: 'A',
            conditions: const {
              r'$or': [
                {'x': 1},
              ],
            },
          ),
        ]).validateRules(),
        throwsA(isA<ConditionFormatException>()),
        reason: 'the default set matches CASL.js exactly',
      );
    });
  });

  group('a custom field reader', () {
    test('reads a model that is neither a Map nor a CaslRecord', () {
      final ability = createMongoAbility(
        [
          RawRule.of(
            action: 'read',
            subject: 'Article',
            conditions: const {'authorId': 7},
          ),
        ],
        read: (target, field) =>
            target is _Article && field == 'authorId' ? target.authorId : null,
      );

      expect(ability.can('read', subject('Article', _Article(7))), isTrue);
      expect(ability.can('read', subject('Article', _Article(8))), isFalse);
    });
  });

  group('a custom fields matcher', () {
    test('replaces the wildcard syntax entirely', () {
      // Case-insensitive exact names, no globbing.
      bool Function(String) matcher(List<String> fields) {
        final lower = fields.map((f) => f.toLowerCase()).toSet();
        return (field) => lower.contains(field.toLowerCase());
      }

      final ability = Ability(
        [
          RawRule.of(
            action: 'read',
            subject: 'A',
            fields: const ['Title'],
          ),
        ],
        fieldsMatcher: matcher,
      );

      expect(ability.can('read', 'A', 'title'), isTrue);
      expect(ability.can('read', 'A', 'body'), isFalse);
    });
  });

  group('G-04 · rules whose conditions are not a Mongo query', () {
    // CASL.js supports this by letting `conditions` be a function. We keep it a
    // map on purpose — a closure cannot be serialised, and a rule that cannot
    // travel contradicts the whole premise. A named predicate gets the same
    // expressiveness *and* stays on the wire.
    final predicates = <String, bool Function(Object? subject)>{
      'ownedByMe': (subject) => subject is Map && subject['authorId'] == 7,
    };

    ConditionsMatch matcher(Map<String, Object?> conditions) {
      final name = conditions['predicate'];
      return name is String
          ? _PredicateMatch(predicates[name]!)
          : MongoConditionsMatch(conditions);
    }

    final rules = [
      RawRule.of(
        action: 'update',
        subject: 'Article',
        conditions: const {'predicate': 'ownedByMe'},
      ),
      RawRule.of(
        action: 'read',
        subject: 'Article',
        conditions: const {'published': true},
      ),
    ];

    final ability = Ability(rules, conditionsMatcher: matcher);

    test('a Dart predicate decides the rule', () {
      expect(
        ability.can('update', subject('Article', const {'authorId': 7})),
        isTrue,
      );
      expect(
        ability.can('update', subject('Article', const {'authorId': 8})),
        isFalse,
      );
    });

    test('Mongo conditions still work in the same ability', () {
      expect(
        ability.can('read', subject('Article', const {'published': true})),
        isTrue,
      );
    });

    test(
      'and the rule still survives a round trip, which a closure would not',
      () {
        final json = jsonEncode([for (final rule in rules) rule.toJson()]);
        final decoded = [
          for (final rule in jsonDecode(json) as List)
            RawRule.fromJson(rule as Map<String, Object?>),
        ];

        expect(decoded, rules);
        expect(
          Ability(
            decoded,
            conditionsMatcher: matcher,
          ).can('update', subject('Article', const {'authorId': 7})),
          isTrue,
        );
      },
    );
  });
}

class _Article {
  _Article(this.authorId);
  final int authorId;
}

/// A [ConditionsMatch] over a plain Dart predicate.
final class _PredicateMatch implements ConditionsMatch {
  const _PredicateMatch(this._test);

  final bool Function(Object? subject) _test;

  @override
  bool matches(Object? subject) => _test(subject);

  // A predicate restricts *something*, or it would not be there — so an
  // inverted rule carrying one cannot forbid a whole subject type.
  @override
  bool get matchesEverything => false;
}
