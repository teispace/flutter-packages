// The findings that are about cost rather than correctness: what a lookup
// remembers, what a check allocates, and what an import lands in your
// namespace.
import 'package:casl/casl.dart';
import 'package:test/test.dart';

void main() {
  group('H-02 · the lookup cache is bounded', () {
    test('an ordinary application never reaches the cap', () {
      final ability = createMongoAbility([
        RawRule.of(action: 'manage', subject: 'all'),
      ]);

      for (final type in ['Article', 'User', 'Invoice']) {
        for (final action in ['read', 'create', 'update', 'delete']) {
          ability.can(action, type);
        }
      }

      // Not an exact count: a lookup for a subject type also caches the
      // wildcard bucket it merged in, and pinning that would be pinning an
      // implementation detail. What matters is the order of magnitude.
      expect(ability.cachedLookupCount, lessThan(512));
      expect(ability.cachedLookupCount, greaterThan(0));
    });

    test('and an adversarial one cannot grow it without bound', () {
      // Both halves of the key can come from data — a subject type read out of
      // a payload, an action out of a deep link — so an unbounded map keyed by
      // whatever a caller passes is a slow leak.
      final ability = createMongoAbility([
        RawRule.of(action: 'manage', subject: 'all'),
      ]);

      for (var i = 0; i < 5000; i++) {
        ability.can('action$i', 'Type$i');
      }

      expect(ability.cachedLookupCount, lessThanOrEqualTo(512));
    });

    test('past the cap the answers are still right', () {
      final ability = createMongoAbility([
        RawRule.of(action: 'manage', subject: 'all'),
        RawRule.of(action: 'delete', subject: 'Invoice', inverted: true),
      ]);

      for (var i = 0; i < 5000; i++) {
        ability.can('action$i', 'Type$i');
      }

      expect(ability.can('read', 'Article'), isTrue);
      expect(ability.can('delete', 'Invoice'), isFalse);
    });

    test('and updating the rules empties it', () {
      final ability = createMongoAbility([
        RawRule.of(action: 'read', subject: 'Article'),
      ]);

      expect(ability.can('read', 'Article'), isTrue);
      expect(ability.cachedLookupCount, greaterThan(0));

      ability.update([RawRule.of(action: 'read', subject: 'Article')]);
      expect(ability.cachedLookupCount, 0);
    });
  });

  group('H-03 · a check with nothing to filter allocates nothing', () {
    test('rulesFor hands back the very list possibleRulesFor built', () {
      final ability = createMongoAbility([
        RawRule.of(action: 'read', subject: 'Article'),
        RawRule.of(action: 'update', subject: 'Article', fields: const ['t']),
      ]);

      // `identical`, not `equals`: the point is that no copy was made. This
      // runs once per row of a list, and the rule set having *any* per-field
      // rule used to be enough to allocate on every call.
      expect(
        identical(
          ability.rulesFor('read', 'Article'),
          ability.possibleRulesFor('read', 'Article'),
        ),
        isTrue,
      );
    });

    test('and still filters when there is something to filter', () {
      final ability = createMongoAbility([
        RawRule.of(action: 'update', subject: 'Article'),
        RawRule.of(
          action: 'update',
          subject: 'Article',
          fields: const ['secret'],
          inverted: true,
        ),
      ]);

      expect(ability.rulesFor('update', 'Article', 'title'), hasLength(1));
      expect(ability.rulesFor('update', 'Article', 'secret'), hasLength(2));
    });

    test('including when the first rule is the one dropped', () {
      // The lazy copy starts as "everything kept so far", so dropping the
      // element at index 0 has to produce an empty list rather than skip the
      // allocation.
      final ability = createMongoAbility([
        RawRule.of(action: 'read', subject: 'Article', fields: const ['a']),
        RawRule.of(action: 'read', subject: 'Article', fields: const ['b']),
      ]);

      expect(ability.rulesFor('read', 'Article', 'b'), hasLength(1));
      expect(ability.rulesFor('read', 'Article', 'c'), isEmpty);
    });
  });

  group('H-01 · what an import lands in your namespace', () {
    test('the leaked internals are gone', () {
      // Nothing to assert at runtime — the assertion is that this file
      // compiles while `test/type_safety/exports_are_narrow.dart` does not.
      // See that file for the list and the reasoning.
      expect(subject('Article', const {}), isNotNull);
    });

    test('what replaced them still works', () {
      expect(CaslFields.read(const {'a': 1}, 'a'), 1);
      expect(CaslFields.has(const {'a': null}, 'a'), isTrue);
      expect(CaslFields.has(const <String, Object?>{}, 'a'), isFalse);
      expect(
        CaslFields.path(const {
          'a': {'b': 2},
        }, 'a.b'),
        2,
      );
      expect(
        CaslFields.parent(const {
          'a': {'b': 2},
        }, 'a.b'),
        (const {'b': 2}, 'b'),
      );
      expect(Condition.always, isA<CompoundCondition>());
      expect(Condition.never, isA<CompoundCondition>());
    });

    test('an empty and is satisfied, an empty or is not', () {
      // Which is the whole reason those two constants exist.
      const interpreter = ConditionInterpreter();

      expect(interpreter.interpret(Condition.always, const {}), isTrue);
      expect(interpreter.interpret(Condition.never, const {}), isFalse);
    });
  });
}
