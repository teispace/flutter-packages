import 'dart:convert';

import 'package:casl/casl.dart';
import 'package:test/test.dart';

void main() {
  group('packing', () {
    test('the common rule is two strings', () {
      // The whole reason the format exists. A grant is a few hundred rules on
      // every sign-in, and most of them carry nothing but an action and a
      // subject — six keys and their names would be mostly punctuation.
      expect(
        packRules([RawRule.of(action: 'read', subject: 'Article')]),
        [
          ['read', 'Article'],
        ],
      );
    });

    test('several actions or subjects are comma-joined', () {
      expect(
        packRules([
          RawRule.of(
            action: const ['read', 'update'],
            subject: const ['Article', 'Comment'],
          ),
        ]),
        [
          ['read,update', 'Article,Comment'],
        ],
      );
    });

    test('conditions ride in the third slot', () {
      expect(
        packRules([
          RawRule.of(
            action: 'update',
            subject: 'Article',
            conditions: const {'authorId': 7},
          ),
        ]),
        [
          [
            'update',
            'Article',
            {'authorId': 7},
          ],
        ],
      );
    });

    test('an empty slot before a full one keeps its place as a zero', () {
      // The positions are fixed, so a rule with fields and no conditions has
      // to say so. Dropping the zero would shift `fields` into `conditions`.
      expect(
        packRules([
          RawRule.of(
            action: 'update',
            subject: 'Article',
            fields: const ['title', 'body'],
          ),
        ]),
        [
          ['update', 'Article', 0, 0, 'title,body'],
        ],
      );
    });

    test('a reason keeps every zero before it', () {
      expect(
        packRules([
          RawRule.of(
            action: 'delete',
            subject: 'Article',
            inverted: true,
            reason: 'published articles are kept',
          ),
        ]),
        [
          ['delete', 'Article', 0, 1, 0, 'published articles are kept'],
        ],
      );
    });

    test('subject types can be renamed on the way out', () {
      expect(
        packRules(
          [RawRule.of(action: 'read', subject: 'Article')],
          packSubject: (type) => type.toLowerCase(),
        ),
        [
          ['read', 'article'],
        ],
      );
    });
  });

  group('unpacking', () {
    test('reads a short array without complaint — that is the format', () {
      final rules = unpackRules([
        ['read', 'Article'],
      ]);

      expect(rules.single.actions, ['read']);
      expect(rules.single.subjects, ['Article']);
      expect(rules.single.inverted, isFalse);
      expect(rules.single.conditions, isNull);
    });

    test('reads every slot when they are all there', () {
      final rules = unpackRules([
        [
          'read,update',
          'Article',
          {'authorId': 7},
          1,
          'title,body',
          'not yours',
        ],
      ]);
      final rule = rules.single;

      expect(rule.actions, ['read', 'update']);
      expect(rule.conditions, {'authorId': 7});
      expect(rule.inverted, isTrue);
      expect(rule.fields, ['title', 'body']);
      expect(rule.reason, 'not yours');
    });

    test('a zero placeholder is not a value', () {
      final rule = unpackRules([
        ['read', 'Article', 0, 0, 0],
      ]).single;

      expect(rule.conditions, isNull);
      expect(rule.fields, isNull);
      expect(rule.inverted, isFalse);
    });

    test('a rule with no action is refused, not guessed at', () {
      // Everything else has a sensible absence. An action does not: a rule
      // that permits nothing in particular would match nothing, silently.
      expect(() => unpackRules([<Object?>[]]), throwsFormatException);
      expect(() => unpackRules(['read']), throwsFormatException);
    });
  });

  group('the round trip', () {
    test('survives JSON, which is the only trip that matters', () {
      // The rules are computed on a server and read by a client. Anything that
      // does not survive `jsonEncode` never arrives.
      final original = [
        RawRule.of(action: 'manage', subject: 'all'),
        RawRule.of(
          action: const ['read', 'update'],
          subject: 'Article',
          conditions: const {
            'authorId': 7,
            'status': {
              r'$in': ['draft', 'review'],
            },
          },
          fields: const ['title', 'body'],
        ),
        RawRule.of(
          action: 'delete',
          subject: 'Article',
          inverted: true,
          reason: 'published articles are kept',
        ),
      ];

      final wire = jsonDecode(jsonEncode(packRules(original))) as List<Object?>;

      expect(unpackRules(wire), original);
    });

    test('and the unpacked rules still answer questions', () {
      final packed = packRules([
        RawRule.of(
          action: 'update',
          subject: 'Article',
          conditions: const {'authorId': 7},
        ),
      ]);
      final ability = createMongoAbility(
        unpackRules(jsonDecode(jsonEncode(packed)) as List<Object?>),
      );

      expect(
        ability.can('update', subject('Article', const {'authorId': 7})),
        isTrue,
      );
      expect(
        ability.can('update', subject('Article', const {'authorId': 8})),
        isFalse,
      );
    });

    test('a payload written by CASL.js is read unchanged', () {
      // Pasted from `packRules` in @casl/ability v7. If this ever stops
      // parsing, the two halves of a product have stopped agreeing.
      const payload = '''
[["manage","all"],
 ["read,update","Article",{"authorId":7}],
 ["delete","Article",0,1,0,"published articles are kept"]]
''';

      final rules = unpackRules(jsonDecode(payload) as List<Object?>);
      final ability = createMongoAbility(rules);

      expect(ability.can('read', 'Comment'), isTrue);
      expect(
        ability.can('update', subject('Article', const {'authorId': 7})),
        isTrue,
      );
      expect(ability.can('delete', 'Article'), isFalse);
      expect(
        ability.relevantRuleFor('delete', 'Article')?.reason,
        'published articles are kept',
      );
    });
  });

  group('ForbiddenError', () {
    final ability = createMongoAbility([
      RawRule.of(action: 'read', subject: 'Article'),
      RawRule.of(
        action: 'delete',
        subject: 'Article',
        inverted: true,
        reason: 'published articles are kept',
      ),
    ]);

    test('does not throw when the action is permitted', () {
      expect(() => ability.throwUnlessCan('read', 'Article'), returnsNormally);
    });

    test('throws when it is not', () {
      expect(
        () => ability.throwUnlessCan('delete', 'Article'),
        throwsA(isA<ForbiddenError>()),
      );
    });

    test("uses the rule's own words when it has any", () {
      // The difference between "you cannot do that" and a sentence that tells
      // the user something they can act on.
      final error = ability.errorUnlessCan('delete', 'Article');

      expect(error?.message, 'published articles are kept');
      expect(error?.reason, 'published articles are kept');
    });

    test('falls back to a description when no rule explained itself', () {
      // Nothing granted `publish` at all, so there is no rule to ask why.
      final error = ability.errorUnlessCan('publish', 'Article');

      expect(error?.reason, isNull);
      expect(error?.message, 'Cannot execute "publish" on "Article"');
    });

    test('a message at the call site wins over both', () {
      final error = ability.errorUnlessCan(
        'delete',
        'Article',
        null,
        'this article is referenced by an invoice',
      );

      expect(error?.message, 'this article is referenced by an invoice');
    });

    test('carries what was refused, not only that something was', () {
      final error = ability.errorUnlessCan('update', 'Article', 'title');

      expect(error?.action, 'update');
      expect(error?.subjectType, 'Article');
      expect(error?.field, 'title');
    });

    test('the default description is replaceable, for translation', () {
      final original = ForbiddenError.describe;
      addTearDown(() => ForbiddenError.describe = original);

      ForbiddenError.describe = (e) => 'nope: ${e.action}';

      expect(
        ability.errorUnlessCan('publish', 'Article')?.message,
        'nope: publish',
      );
    });

    test('errorUnlessCan reports rather than raises', () {
      // For putting the reason beside a disabled button instead of throwing at
      // a user who has not done anything yet.
      expect(ability.errorUnlessCan('read', 'Article'), isNull);
      expect(ability.errorUnlessCan('delete', 'Article'), isNotNull);
    });
  });
}
