// Tests that pin fixed defects, each named for its entry in docs/PARITY.md.
//
// The parity fixtures cover anything expressible as "CASL.js answers X". These
// are the rest: a crash, an option that quietly disabled another, and a default
// that made the documented example throw. None of those are a divergence in the
// answer, so none of them would ever have shown up there.
import 'package:casl/casl.dart';
import 'package:test/test.dart';

void main() {
  group('D-03 · a rule reached by two index paths appears once', () {
    test('when its actions include the wildcard action', () {
      final ability = createMongoAbility([
        RawRule.of(action: const ['read', 'manage'], subject: 'Article'),
      ]);

      expect(ability.possibleRulesFor('read', 'Article'), hasLength(1));
    });

    test('when its subjects include the wildcard subject type', () {
      final ability = createMongoAbility([
        RawRule.of(action: 'read', subject: const ['Article', 'all']),
      ]);

      expect(ability.possibleRulesFor('read', 'Article'), hasLength(1));
    });

    test('so a query gets one branch rather than two identical ones', () {
      // The visible cost of the duplicate. `can` was always right; this was
      // not — `rulesToAst` emitted `(or x eq 1 x eq 1)`.
      final ability = createMongoAbility([
        RawRule.of(
          action: const ['read', 'manage'],
          subject: 'Article',
          conditions: const {'x': 1},
        ),
      ]);

      expect(
        rulesToAst(ability, 'read', 'Article'),
        isA<FieldCondition>()
            .having((c) => c.operator, 'operator', 'eq')
            .having((c) => c.field, 'field', 'x'),
      );
    });

    test('and ordering across the merge is still by priority', () {
      // The fix touches the merge, so pin what the merge is actually for.
      final ability = createMongoAbility([
        RawRule.of(action: 'read', subject: 'all'),
        RawRule.of(action: 'manage', subject: 'Article'),
        RawRule.of(action: 'read', subject: 'Article'),
      ]);

      final priorities = ability
          .possibleRulesFor('read', 'Article')
          .map((rule) => rule.priority)
          .toList();

      expect(priorities, [0, 1, 2]);
    });
  });

  group('D-04 · a listener may unsubscribe while it is being called', () {
    test('itself', () {
      final ability = createMongoAbility(const []);
      var calls = 0;

      late void Function() unsubscribe;
      unsubscribe = ability.on('updated', (_) {
        calls++;
        unsubscribe();
      });

      expect(() => ability.update(const []), returnsNormally);
      ability.update(const []);

      expect(calls, 1, reason: 'it unsubscribed after the first call');
    });

    test('another listener, which then does not run', () {
      final ability = createMongoAbility(const []);
      final called = <String>[];

      late void Function() unsubscribeSecond;
      ability.on('updated', (_) {
        called.add('first');
        unsubscribeSecond();
      });
      unsubscribeSecond = ability.on('updated', (_) => called.add('second'));

      expect(() => ability.update(const []), returnsNormally);

      // Dispatching over a copy means the removed listener is still in the
      // snapshot, so it runs once more. That matches CASL.js, which collects
      // handlers up front for the same reason.
      expect(called, ['first', 'second']);

      called.clear();
      ability.update(const []);
      expect(called, ['first']);
    });

    test('during the "update" event, before the rules change', () {
      final ability = createMongoAbility(const []);
      late void Function() unsubscribe;
      unsubscribe = ability.on('update', (_) => unsubscribe());

      expect(() => ability.update(const []), returnsNormally);
    });
  });

  group('D-05 · a custom detectSubjectType defers rather than replaces', () {
    test('subject() still works when the detector returns null', () {
      final ability = createMongoAbility(
        [RawRule.of(action: 'read', subject: 'Article')],
        detectSubjectType: (value) => null,
      );

      expect(ability.can('read', subject('Article', const {})), isTrue);
    });

    test('CaslSubject still works when the detector returns null', () {
      final ability = createMongoAbility(
        [RawRule.of(action: 'read', subject: 'Note')],
        detectSubjectType: (value) => null,
      );

      expect(ability.can('read', _Note()), isTrue);
    });

    test('and the detector still wins where it answers', () {
      final ability = createMongoAbility(
        [RawRule.of(action: 'read', subject: 'FromDetector')],
        detectSubjectType: (value) => value is _Note ? 'FromDetector' : null,
      );

      expect(ability.can('read', _Note()), isTrue);
    });

    test('detectSubjectType reports what a check would have used', () {
      final ability = createMongoAbility(
        const [],
        detectSubjectType: (value) => null,
      );

      expect(
        ability.detectSubjectType(subject('Article', const {})),
        'Article',
      );
      expect(ability.detectSubjectType(_Note()), 'Note');
    });
  });

  group('DOC-02 · the documented builder example works', () {
    test('build() understands conditions without being told to', () {
      // This threw before: `build()` defaulted to a bare `Ability`, which has
      // no conditions matcher, so a correctly written rule failed at build
      // time with an error about an option the caller had never heard of.
      final ability =
          (AbilityBuilder()
                ..can('read', 'Article')
                ..can('update', 'Article', {'authorId': 7}))
              .build();

      expect(ability.can('read', 'Article'), isTrue);
      final mine = subject('Article', const {'authorId': 7});
      final theirs = subject('Article', const {'authorId': 8});
      expect(ability.can('update', mine), isTrue);
      expect(ability.can('update', theirs), isFalse);
    });

    test('create: still overrides it', () {
      final ability = (AbilityBuilder()..can('read', 'Article')).build(
        create: (rules) => Ability(rules, anySubjectTypeName: 'everything'),
      );

      expect(ability.anySubjectTypeName, 'everything');
    });

    test('fields and conditions are positional, in that order', () {
      // DOC-01: the dartdoc used to pass these as named arguments, which does
      // not compile. This test is the reason that cannot happen again.
      final ability =
          (AbilityBuilder()..can(
                'update',
                'Article',
                const {'authorId': 7},
                const ['title'],
              ))
              .build();

      final mine = subject('Article', const {'authorId': 7});
      expect(ability.can('update', mine, 'title'), isTrue);
      expect(ability.can('update', mine, 'body'), isFalse);
    });
  });
}

class _Note with CaslSubject {
  @override
  String get caslSubjectType => 'Note';
}
