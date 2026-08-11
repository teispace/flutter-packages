import 'package:casl/casl.dart';
import 'package:test/test.dart';

void main() {
  Ability abilityOf(List<RawRule> rules) => createMongoAbility(rules);

  /// A readable rendering of a condition tree, so the assertions below say
  /// what the query *is* rather than poking at its parts.
  String render(Condition? condition) => switch (condition) {
    null => 'nothing',
    CompoundCondition(:final operator, :final conditions)
        when conditions.isEmpty =>
      operator == 'and' ? 'everything' : '$operator()',
    CompoundCondition(:final operator, :final conditions) =>
      '$operator(${conditions.map(render).join(', ')})',
    FieldCondition(:final operator, :final field, :final value) =>
      '$field $operator $value',
  };

  group('what a query has to say', () {
    test('nothing permitted is null, not an empty filter', () {
      // The distinction that decides whether an unauthorised user sees an
      // empty list or the entire table. They are not the same answer and must
      // not share a representation.
      expect(rulesToAst(abilityOf(const []), 'read', 'Article'), isNull);
    });

    test('everything permitted excludes nothing', () {
      final ability = abilityOf([
        RawRule.of(action: 'read', subject: 'Article'),
      ]);

      expect(render(rulesToAst(ability, 'read', 'Article')), 'everything');
    });

    test('one conditional rule is that condition', () {
      final ability = abilityOf([
        RawRule.of(
          action: 'read',
          subject: 'Article',
          conditions: const {'authorId': 7},
        ),
      ]);

      expect(render(rulesToAst(ability, 'read', 'Article')), 'authorId eq 7');
    });

    test('several conditional rules are alternatives', () {
      final ability = abilityOf([
        RawRule.of(
          action: 'read',
          subject: 'Article',
          conditions: const {'authorId': 7},
        ),
        RawRule.of(
          action: 'read',
          subject: 'Article',
          conditions: const {'published': true},
        ),
      ]);

      expect(
        render(rulesToAst(ability, 'read', 'Article')),
        'or(published eq true, authorId eq 7)',
      );
    });
  });

  group('flattening the priority order — the subtle part', () {
    test('a forbidding rule bounds every permitting rule below it', () {
      // Note the declaration order: the LAST rule written has the HIGHEST
      // priority, so `cannot(secret)` is evaluated first and `can(authorId)`
      // is only reached when it did not apply. A query has no such ordering,
      // so that sequence has to become "and not".
      final ability = abilityOf([
        RawRule.of(
          action: 'read',
          subject: 'Article',
          conditions: const {'authorId': 7},
        ),
        RawRule.of(
          action: 'read',
          subject: 'Article',
          conditions: const {'secret': true},
          inverted: true,
        ),
      ]);

      expect(
        render(rulesToAst(ability, 'read', 'Article')),
        'and(authorId eq 7, not(secret eq true))',
      );
    });

    test('but not the rules ABOVE it', () {
      // Reaching a higher-priority rule means the forbidding one below never
      // ran. Bounding it too would refuse records the user may actually see.
      final ability = abilityOf([
        RawRule.of(
          action: 'read',
          subject: 'Article',
          conditions: const {'published': true},
        ),
        RawRule.of(
          action: 'read',
          subject: 'Article',
          conditions: const {'authorId': 7},
          inverted: true,
        ),
        RawRule.of(
          action: 'read',
          subject: 'Article',
          conditions: const {'pinned': true},
        ),
      ]);

      // `pinned` was written last, so it is highest priority and unbounded;
      // `published` sits below the forbidding rule and is bounded by it.
      expect(
        render(rulesToAst(ability, 'read', 'Article')),
        'or(pinned eq true, and(published eq true, not(authorId eq 7)))',
      );
    });

    test('an unconditional cannot ends the walk', () {
      // It refuses every record, so nothing below it can contribute — and
      // since it is the highest priority here, the answer is nothing at all.
      final ability = abilityOf([
        RawRule.of(
          action: 'read',
          subject: 'Article',
          conditions: const {'authorId': 7},
        ),
        RawRule.of(action: 'read', subject: 'Article', inverted: true),
      ]);

      expect(rulesToAst(ability, 'read', 'Article'), isNull);
    });

    test('an unconditional can ends it too, bounded by what came before', () {
      // "Everything except the secret ones", which is the shape a real grant
      // usually has.
      final ability = abilityOf([
        RawRule.of(action: 'read', subject: 'Article'),
        RawRule.of(
          action: 'read',
          subject: 'Article',
          conditions: const {'secret': true},
          inverted: true,
        ),
      ]);

      expect(
        render(rulesToAst(ability, 'read', 'Article')),
        'not(secret eq true)',
      );
    });

    test('and combines with the branches above it', () {
      final ability = abilityOf([
        RawRule.of(action: 'read', subject: 'Article'),
        RawRule.of(
          action: 'read',
          subject: 'Article',
          conditions: const {'pinned': true},
        ),
        RawRule.of(
          action: 'read',
          subject: 'Article',
          conditions: const {'secret': true},
          inverted: true,
        ),
      ]);

      expect(
        render(rulesToAst(ability, 'read', 'Article')),
        'or(and(pinned eq true, not(secret eq true)), not(secret eq true))',
      );
    });

    test('the query agrees with can(), record by record', () {
      // The property that actually matters, and the one a hand-checked
      // expected string cannot prove on its own.
      final ability = abilityOf([
        RawRule.of(
          action: 'read',
          subject: 'Article',
          conditions: const {'secret': true},
          inverted: true,
        ),
        RawRule.of(
          action: 'read',
          subject: 'Article',
          conditions: const {'authorId': 7},
        ),
        RawRule.of(
          action: 'read',
          subject: 'Article',
          conditions: const {'published': true},
        ),
      ]);

      const rows = [
        {'authorId': 7, 'published': false, 'secret': false},
        {'authorId': 9, 'published': true, 'secret': false},
        {'authorId': 7, 'published': true, 'secret': true},
        {'authorId': 9, 'published': false, 'secret': false},
      ];

      final query = rulesToAst(ability, 'read', 'Article')!;
      const interpreter = ConditionInterpreter();

      for (final row in rows) {
        expect(
          interpreter.interpret(query, row),
          ability.can('read', subject('Article', row)),
          reason: 'the query and can() disagreed about $row',
        );
      }
    });
  });

  group('building for another language', () {
    test('the algorithm is reusable, which is the point of the hooks', () {
      // Proving the seam works, with a language whose parts are strings. A
      // real one would build a Drift expression or a SQL fragment.
      final ability = abilityOf([
        RawRule.of(
          action: 'read',
          subject: 'Article',
          conditions: const {'authorId': 7},
        ),
        RawRule.of(
          action: 'read',
          subject: 'Article',
          conditions: const {'secret': true},
          inverted: true,
        ),
      ]);

      final sql = rulesToCondition<String>(
        ability.rulesFor('read', 'Article'),
        (rule) => rule.conditions!.entries
            .map((e) => '${e.key} = ${e.value}')
            .join(' AND '),
        QueryLanguage(
          // Collapsing a single part is the builder's job, not the
          // algorithm's — it hands over whatever it has and lets the language
          // decide how to render one.
          and: (parts) =>
              parts.length == 1 ? parts.single : '(${parts.join(' AND ')})',
          or: (parts) =>
              parts.length == 1 ? parts.single : '(${parts.join(' OR ')})',
          not: (part) => 'NOT ($part)',
          unrestricted: () => '1 = 1',
        ),
      );

      expect(sql, '(authorId = 7 AND NOT (secret = true))');
    });

    test('a rule whose conditions were never parsed refuses to guess', () {
      // Skipping it would widen the query, and a query returning records the
      // user may not see is the failure this function exists to prevent.
      final ability = Ability(
        [
          RawRule.of(
            action: 'read',
            subject: 'Article',
            conditions: const {'authorId': 7},
          ),
        ],
        conditionsMatcher: (_) => _OpaqueMatch(),
      );

      expect(
        () => rulesToAst(ability, 'read', 'Article'),
        throwsA(isA<StateError>()),
      );
    });
  });
}

/// A matcher that answers questions but cannot describe itself.
final class _OpaqueMatch implements ConditionsMatch {
  @override
  bool matches(Object? subject) => true;

  @override
  bool get matchesEverything => false;
}
