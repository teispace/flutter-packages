// The v7 surface that had no Dart equivalent, each test named for its finding.
//
// These exist to make a CASL.js example transliterate. Where a shape here looks
// un-Dart-like — a chain that could be a cascade, a static that could be a
// setter — that is the reason, and it is stated at the declaration.
import 'package:casl/casl.dart';
import 'package:test/test.dart';

void main() {
  tearDown(ForbiddenError.resetDefaultMessage);

  group('G-01 · defineAbility', () {
    test('builds an ability in one expression', () {
      final ability = defineAbility((can, cannot) {
        can('read', 'Article');
        can('update', 'Article', {'authorId': 7});
        cannot('delete', 'Article', {'published': true});
      });

      expect(ability.can('read', 'Article'), isTrue);
      expect(
        ability.can('update', subject('Article', const {'authorId': 7})),
        isTrue,
      );
      expect(
        ability.can('delete', subject('Article', const {'published': true})),
        isFalse,
      );
    });

    test('understands conditions without being handed a factory', () {
      // The whole point of the default: `defineAbility` is what CASL's docs
      // reach for, and it would be useless if conditions threw.
      expect(
        () => defineAbility((can, _) => can('read', 'A', {'x': 1})),
        returnsNormally,
      );
    });

    test('the callback parameters can be renamed at the call site', () {
      // CASL's cookbook has a page arguing for `allow`/`forbid`, because `can`
      // next to `ability.can` confuses people. Nothing here should prevent it.
      final ability = defineAbility((allow, forbid) {
        allow('read', 'Post');
        forbid('read', 'Post', {'private': true});
      });

      expect(
        ability.can('read', subject('Post', const {'private': false})),
        isTrue,
      );
      expect(
        ability.can('read', subject('Post', const {'private': true})),
        isFalse,
      );
    });

    test('carries a reason through .because()', () {
      final ability = defineAbility((can, cannot) {
        can('delete', 'Article');
        cannot('delete', 'Article', {
          'published': true,
        }).because('published articles are kept for the audit trail');
      });

      final refusal = ability.errorUnlessCan(
        'delete',
        subject('Article', const {'published': true}),
      );

      expect(
        refusal?.message,
        'published articles are kept for the audit trail',
      );
    });

    test('create: chooses what gets built', () {
      final ability = defineAbility(
        (can, _) => can('read', 'A'),
        create: (rules) => Ability(rules, anySubjectTypeName: 'everything'),
      );

      expect(ability.anySubjectTypeName, 'everything');
    });

    test('defineAbilityAsync awaits the definition first', () async {
      Future<bool> loadReadOnlyFlag() async => true;

      final ability = await defineAbilityAsync((can, cannot) async {
        can('manage', 'all');
        if (await loadReadOnlyFlag()) cannot('update', 'all');
      });

      expect(ability.can('read', 'Article'), isTrue);
      expect(ability.can('update', 'Article'), isFalse);
    });
  });

  group('G-02 · AbilityBuilder takes a factory', () {
    test('defaults to createMongoAbility', () {
      final ability = (AbilityBuilder()..can('read', 'A', {'x': 1})).build();

      expect(ability.can('read', subject('A', const {'x': 1})), isTrue);
    });

    test('the constructor factory is used by build()', () {
      final builder = AbilityBuilder(
        (rules) => Ability(rules, anyActionName: 'everything'),
      )..can('everything', 'A');

      expect(builder.build().can('read', 'A'), isTrue);
    });

    test('build(create:) overrides the constructor factory for one call', () {
      final builder = AbilityBuilder(
        (rules) => Ability(rules, anyActionName: 'never-used'),
      )..can('read', 'A');

      final ability = builder.build(
        create: (rules) => Ability(rules, anyActionName: 'used'),
      );

      expect(ability.anyActionName, 'used');
    });

    test('because() is chainable, as CASL.js RuleBuilder is', () {
      final builder = AbilityBuilder()
        ..can('read', 'A')
        ..cannot('read', 'A', {'secret': true}).because('it is secret');

      expect(builder.rules.last.reason, 'it is secret');
    });
  });

  group('G-05 · ForbiddenError', () {
    final ability = defineAbility((can, cannot) {
      can('read', 'Post');
      cannot('update', 'Post', {'locked': true}).because('the post is locked');
    });

    test('from().throwUnlessCan() throws when refused', () {
      expect(
        () => ForbiddenError.from(ability).throwUnlessCan('update', 'Article'),
        throwsA(isA<ForbiddenError>()),
      );
    });

    test('from().throwUnlessCan() is silent when permitted', () {
      expect(
        () => ForbiddenError.from(ability).throwUnlessCan('read', 'Post'),
        returnsNormally,
      );
    });

    test('setMessage() wins over the rule and the default', () {
      final error = ForbiddenError.from(ability)
          .setMessage('You cannot update posts')
          .unlessCan('update', subject('Post', const {'locked': true}));

      expect(error?.message, 'You cannot update posts');
    });

    test('setMessage() returns a new check rather than mutating', () {
      // A shared base check must not change underneath whoever holds it.
      final base = ForbiddenError.from(ability);
      final withMessage = base.setMessage('custom');

      expect(withMessage.unlessCan('update', 'Nope')?.message, 'custom');
      expect(
        base.unlessCan('update', 'Nope')?.message,
        'Cannot execute "update" on "Nope"',
      );
    });

    test('without a message, the rule speaks', () {
      final error = ForbiddenError.from(
        ability,
      ).unlessCan('update', subject('Post', const {'locked': true}));

      expect(error?.message, 'the post is locked');
      expect(error?.reason, 'the post is locked');
    });

    test('the error carries the ability that refused', () {
      final error = ForbiddenError.from(ability).unlessCan('update', 'Article');

      expect(error?.ability, same(ability));
    });

    test('setDefaultMessage takes a string', () {
      ForbiddenError.setDefaultMessage('Not authorised');

      expect(
        ForbiddenError.from(ability).unlessCan('update', 'Article')?.message,
        'Not authorised',
      );
    });

    test('describe takes a builder, and infers its parameter', () {
      // The other half of CASL.js's `setDefaultMessage`. Spelled as a field so
      // the closure's parameter type is inferred rather than annotated.
      ForbiddenError.describe = (e) =>
          'You may not ${e.action} a ${e.subjectType}';

      expect(
        ForbiddenError.from(ability).unlessCan('update', 'Article')?.message,
        'You may not update a Article',
      );
    });
  });

  group('G-06 · AccessibleFields', () {
    final ability = defineAbility((can, cannot) {
      can('read', 'Article');
      cannot('read', 'Article', null, ['secret']);
      can('read', 'User', null, ['name']);
    });

    final fields = AccessibleFields(
      ability,
      'read',
      allFieldsOf: (type) => switch (type) {
        'Article' => ['title', 'body', 'secret'],
        'User' => ['name', 'email'],
        _ => const [],
      },
    );

    test('ofType answers for the whole type', () {
      expect(fields.ofType('Article'), ['title', 'body']);
      expect(fields.ofType('User'), ['name']);
    });

    test('of answers for one instance, conditions evaluated', () {
      final scoped = AccessibleFields(
        defineAbility((can, _) => can('update', 'Article', null, ['title'])),
        'update',
        allFieldsOf: (_) => ['title', 'body'],
      );

      expect(scoped.of(subject('Article', const {})), ['title']);
    });

    test('of detects the subject type the same way a check would', () {
      expect(fields.of(subject('Article', const {})), ['title', 'body']);
    });
  });

  group('validateRules · when an unreadable rule is found', () {
    List<RawRule> withUnknownOperator() => [
      RawRule.of(
        action: 'read',
        subject: 'A',
        conditions: const {
          r'$or': [
            {'x': 1},
          ],
        },
      ),
      RawRule.of(action: 'read', subject: 'B'),
    ];

    test('not while building — conditions compile lazily', () {
      expect(
        () => createMongoAbility(withUnknownOperator()),
        returnsNormally,
      );
    });

    test('not while checking a subject type — nothing to evaluate against', () {
      // The lazier half, and the surprising one: a permitting rule checked
      // against a type answers yes without ever looking at its conditions.
      final ability = createMongoAbility(withUnknownOperator());

      expect(ability.can('read', 'A'), isTrue);
    });

    test('but on the first instance checked, which is a screen', () {
      final ability = createMongoAbility(withUnknownOperator());

      expect(
        () => ability.can('read', subject('A', const {'x': 1})),
        throwsA(isA<ConditionFormatException>()),
      );
    });

    test('validateRules moves that to a point you choose', () {
      final ability = createMongoAbility(withUnknownOperator());

      expect(ability.validateRules, throwsA(isA<ConditionFormatException>()));
    });

    test('and says nothing when every rule is readable', () {
      final ability = createMongoAbility([
        RawRule.of(action: 'read', subject: 'A', conditions: const {'x': 1}),
        RawRule.of(action: 'read', subject: 'B'),
      ]);

      expect(ability.validateRules, returnsNormally);
    });

    test('deny makes the rule grant nothing instead of throwing', () {
      final ability = createMongoAbility(
        withUnknownOperator(),
        onUnparsableCondition: UnparsableCondition.deny,
      );

      expect(ability.validateRules, returnsNormally);
      expect(ability.can('read', subject('A', const {'x': 1})), isFalse);
      expect(
        ability.can('read', 'B'),
        isTrue,
        reason: 'one unreadable rule must not take the others with it',
      );
    });
  });

  group('G-07 · chaining and event shape', () {
    test('update() returns the ability', () {
      final ability = createMongoAbility(const []);

      expect(
        ability.update([RawRule.of(action: 'read', subject: 'A')]),
        same(ability),
      );
      expect(ability.can('read', 'A'), isTrue);
    });

    test('the event carries target as well as ability', () {
      final ability = createMongoAbility(const []);
      AbilityUpdate? seen;
      ability
        ..on('updated', (event) => seen = event)
        ..update(const []);

      expect(seen?.target, same(ability));
      expect(seen?.target, same(seen?.ability));
    });
  });
}
