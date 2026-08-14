// Action aliases, which had no tests at all until a coverage floor said so.
//
// Worth having for two reasons beyond the number. The README claims we reject
// indirect cycles where CASL.js documents itself as *not* detecting them, and
// an unverified claim in documentation is just a sentence. And alias resolution
// happens once, when the ability is built, so a mistake here is baked into
// every check that follows.
import 'package:casl/casl.dart';
import 'package:test/test.dart';

void main() {
  Ability aliased(Map<String, Object> aliases, List<RawRule> rules) =>
      createMongoAbility(rules, resolveActions: createAliasResolver(aliases));

  group('resolving', () {
    test('an alias grants each action it stands for', () {
      final ability = aliased(
        const {
          'modify': ['update', 'delete'],
        },
        [RawRule.of(action: 'modify', subject: 'Post')],
      );

      expect(ability.can('modify', 'Post'), isTrue);
      expect(ability.can('update', 'Post'), isTrue);
      expect(ability.can('delete', 'Post'), isTrue);
      expect(ability.can('publish', 'Post'), isFalse);
    });

    test('a chain resolves all the way down', () {
      final ability = aliased(
        const {
          'modify': ['update', 'delete'],
          'access': ['read', 'modify'],
        },
        [RawRule.of(action: 'access', subject: 'Post')],
      );

      for (final action in ['access', 'modify', 'read', 'update', 'delete']) {
        expect(ability.can(action, 'Post'), isTrue, reason: action);
      }
    });

    test('but only in one direction', () {
      // Granting both halves does not grant the alias. CASL is explicit about
      // this and it surprises people: an alias is shorthand for writing a rule,
      // not a claim about what a set of actions adds up to.
      final ability = aliased(
        const {
          'modify': ['update', 'delete'],
        },
        [
          RawRule.of(action: const ['update', 'delete'], subject: 'Post'),
        ],
      );

      expect(ability.can('update', 'Post'), isTrue);
      expect(ability.can('delete', 'Post'), isTrue);
      expect(ability.can('modify', 'Post'), isFalse);
    });

    test('a single string is as good as a list', () {
      final ability = aliased(
        const {'edit': 'update'},
        [RawRule.of(action: 'edit', subject: 'Post')],
      );

      expect(ability.can('update', 'Post'), isTrue);
    });

    test('an action with no alias is left alone', () {
      final ability = aliased(
        const {
          'modify': ['update'],
        },
        [RawRule.of(action: 'read', subject: 'Post')],
      );

      expect(ability.can('read', 'Post'), isTrue);
      expect(ability.can('update', 'Post'), isFalse);
    });

    test('and each action appears once, however many paths reach it', () {
      // `access` reaches `update` through `modify` and directly. The resolver
      // deduplicates, so the rule is not indexed twice — which is the same
      // class of bug the rule index had in D-03.
      final resolve = createAliasResolver(const {
        'modify': ['update', 'delete'],
        'access': ['modify', 'update'],
      });

      expect(resolve(['access']), ['access', 'modify', 'update', 'delete']);
    });
  });

  group('rejecting', () {
    test('an alias of the wildcard action', () {
      // It would make one alias quietly grant everything.
      expect(
        () => createAliasResolver(const {'access': 'manage'}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('an alias of a custom wildcard action', () {
      expect(
        () => createAliasResolver(
          const {'access': 'ALL'},
          anyActionName: 'ALL',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('the wildcard action as a key', () {
      expect(
        () => createAliasResolver(const {
          'manage': ['read'],
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a direct cycle', () {
      expect(
        () => createAliasResolver(const {
          'access': ['access'],
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('an indirect cycle, which CASL.js does not detect', () {
      // The README says so, which is the reason this test exists.
      expect(
        () => createAliasResolver(const {
          'a': ['b'],
          'b': ['c'],
          'c': ['a'],
        }),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('cycle'),
          ),
        ),
      );
    });

    test('an alias that is neither a string nor a list', () {
      expect(
        () => createAliasResolver(const {'access': 42}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('unless validation is switched off', () {
      // The escape hatch, for a resolver built from data that has already been
      // checked. It only skips the *checking* — a cycle would still hang, which
      // is why it is not the default.
      expect(
        () => createAliasResolver(const {'access': 'manage'}, validate: false),
        returnsNormally,
      );
    });
  });
}
