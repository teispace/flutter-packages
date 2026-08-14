import 'package:casl/casl.dart';
import 'package:test/test.dart';

void main() {
  bool matches(Map<String, Object?> conditions, Object? subject) =>
      MongoConditionsMatch(conditions).matches(subject);

  group('plain values', () {
    test('every key must match — a query is an implicit AND', () {
      expect(matches({'a': 1, 'b': 2}, {'a': 1, 'b': 2}), isTrue);
      expect(matches({'a': 1, 'b': 2}, {'a': 1, 'b': 3}), isFalse);
    });

    test('a missing field does not match', () {
      expect(matches({'a': 1}, <String, Object?>{}), isFalse);
    });

    test('an integer condition matches a decoded double', () {
      // JSON has one number type. A rule written `{views: 100}` on the server
      // must match a body that decoded `100.0`, or the same rule means
      // different things on either side of the wire.
      expect(matches({'views': 100}, {'views': 100.0}), isTrue);
    });

    test('an empty query matches everything', () {
      expect(matches({}, {'anything': true}), isTrue);
      expect(MongoConditionsMatch(const {}).matchesEverything, isTrue);
      expect(MongoConditionsMatch(const {'a': 1}).matchesEverything, isFalse);
    });
  });

  group('lists, which is where Mongo stops being obvious', () {
    test('a scalar condition matches if the list CONTAINS it', () {
      // The rule that makes `{tags: 'draft'}` useful. Reading it as "the field
      // equals the string" would make every tag rule silently match nothing.
      expect(
        matches(
          {'tags': 'draft'},
          {
            'tags': ['draft', 'new'],
          },
        ),
        isTrue,
      );
      expect(
        matches(
          {'tags': 'gone'},
          {
            'tags': ['draft', 'new'],
          },
        ),
        isFalse,
      );
    });

    test('and equally if the whole list is equal', () {
      expect(
        matches(
          {
            'tags': ['a', 'b'],
          },
          {
            'tags': ['a', 'b'],
          },
        ),
        isTrue,
      );
      expect(
        matches(
          {
            'tags': ['a', 'b'],
          },
          {
            'tags': ['b', 'a'],
          },
        ),
        isFalse,
      );
    });

    test('a comparison is satisfied by any one element', () {
      expect(
        matches(
          {
            'scores': {r'$gte': 80},
          },
          {
            'scores': [10, 90],
          },
        ),
        isTrue,
      );
      expect(
        matches(
          {
            'scores': {r'$gte': 80},
          },
          {
            'scores': [10, 20],
          },
        ),
        isFalse,
      );
    });
  });

  group('dot notation', () {
    test('reads through nested maps', () {
      expect(
        matches(
          {'author.id': 7},
          {
            'author': {'id': 7},
          },
        ),
        isTrue,
      );
      expect(
        matches(
          {'author.id': 7},
          {
            'author': {'id': 8},
          },
        ),
        isFalse,
      );
    });

    test('a list in the middle is flattened, not indexed', () {
      // `{comments.author: 'ada'}` asks whether ANY comment is Ada's. This is
      // the behaviour that makes ownership rules over collections work at all.
      const article = {
        'comments': [
          {'author': 'ada'},
          {'author': 'bob'},
        ],
      };

      expect(matches({'comments.author': 'ada'}, article), isTrue);
      expect(matches({'comments.author': 'eve'}, article), isFalse);
    });

    test('a numeric segment indexes instead', () {
      const article = {
        'comments': [
          {'author': 'ada'},
          {'author': 'bob'},
        ],
      };

      expect(matches({'comments.0.author': 'ada'}, article), isTrue);
      expect(matches({'comments.1.author': 'ada'}, article), isFalse);
    });

    test('a path through nothing does not match, and does not throw', () {
      // A permission check that crashes is worse than one that denies: the
      // user is already looking at the screen when it is asked.
      expect(matches({'a.b.c': 1}, {'a': 1}), isFalse);
      expect(matches({'a.b.c': 1}, <String, Object?>{}), isFalse);
    });
  });

  group('operators', () {
    test(r'$eq and $ne', () {
      expect(
        matches(
          {
            'a': {r'$eq': 1},
          },
          {'a': 1},
        ),
        isTrue,
      );
      expect(
        matches(
          {
            'a': {r'$ne': 1},
          },
          {'a': 2},
        ),
        isTrue,
      );
      expect(
        matches(
          {
            'a': {r'$ne': 1},
          },
          {'a': 1},
        ),
        isFalse,
      );
    });

    test(r'$lt $lte $gt $gte order numbers, strings and dates', () {
      expect(
        matches(
          {
            'n': {r'$lt': 5},
          },
          {'n': 4},
        ),
        isTrue,
      );
      expect(
        matches(
          {
            'n': {r'$lte': 5},
          },
          {'n': 5},
        ),
        isTrue,
      );
      expect(
        matches(
          {
            'n': {r'$gt': 5},
          },
          {'n': 6},
        ),
        isTrue,
      );
      expect(
        matches(
          {
            'n': {r'$gte': 5},
          },
          {'n': 5},
        ),
        isTrue,
      );
      expect(
        matches(
          {
            's': {r'$gt': 'a'},
          },
          {'s': 'b'},
        ),
        isTrue,
      );
      expect(
        matches(
          {
            'at': {r'$lt': DateTime.utc(2026, 2)},
          },
          {'at': DateTime.utc(2026)},
        ),
        isTrue,
      );
    });

    test('comparing incomparable things denies rather than throwing', () {
      // A condition typed wrongly by a server should not take a screen down.
      expect(
        matches(
          {
            'n': {r'$gt': 5},
          },
          {'n': 'not a number'},
        ),
        isFalse,
      );
    });

    test(r'$in and $nin', () {
      expect(
        matches(
          {
            'a': {
              r'$in': [1, 2],
            },
          },
          {'a': 2},
        ),
        isTrue,
      );
      expect(
        matches(
          {
            'a': {
              r'$in': [1, 2],
            },
          },
          {'a': 3},
        ),
        isFalse,
      );
      expect(
        matches(
          {
            'a': {
              r'$nin': [1, 2],
            },
          },
          {'a': 3},
        ),
        isTrue,
      );
    });

    test(r'$all wants every one of them', () {
      expect(
        matches(
          {
            't': {
              r'$all': ['a', 'b'],
            },
          },
          {
            't': ['a', 'b', 'c'],
          },
        ),
        isTrue,
      );
      expect(
        matches(
          {
            't': {
              r'$all': ['a', 'z'],
            },
          },
          {
            't': ['a', 'b'],
          },
        ),
        isFalse,
      );
    });

    test(r'$size counts a list, and only a list', () {
      expect(
        matches(
          {
            't': {r'$size': 2},
          },
          {
            't': ['a', 'b'],
          },
        ),
        isTrue,
      );
      expect(
        matches(
          {
            't': {r'$size': 2},
          },
          {'t': 'ab'},
        ),
        isFalse,
      );
    });

    test(r'$regex, with $options folded into it', () {
      expect(
        matches(
          {
            's': {r'$regex': '^ab'},
          },
          {'s': 'abc'},
        ),
        isTrue,
      );
      expect(
        matches(
          {
            's': {r'$regex': '^AB'},
          },
          {'s': 'abc'},
        ),
        isFalse,
      );
      expect(
        matches(
          {
            's': {r'$regex': '^AB', r'$options': 'i'},
          },
          {'s': 'abc'},
        ),
        isTrue,
      );
    });

    test(r'a $options flag Dart cannot honour is refused, not ignored', () {
      // Silently dropping `x` would change what the pattern means, which is
      // the kind of authorisation bug that is never traced back.
      expect(
        () => matches(
          {
            's': {r'$regex': 'a b', r'$options': 'x'},
          },
          {'s': 'ab'},
        ),
        throwsA(isA<ConditionFormatException>()),
      );
    });

    test(r'$exists distinguishes absent from null', () {
      expect(
        matches(
          {
            'a': {r'$exists': true},
          },
          {'a': null},
        ),
        isTrue,
      );
      expect(
        matches({
          'a': {r'$exists': true},
        }, <String, Object?>{}),
        isFalse,
      );
      expect(
        matches({
          'a': {r'$exists': false},
        }, <String, Object?>{}),
        isTrue,
      );
    });

    test('a null condition means absent OR null, as in Mongo', () {
      expect(matches({'a': null}, {'a': null}), isTrue);
      expect(matches({'a': null}, <String, Object?>{}), isTrue);
      expect(matches({'a': null}, {'a': 1}), isFalse);
    });

    test(r'$elemMatch tests one element against a whole query', () {
      // The difference from two separate conditions: this demands that ONE
      // element satisfies both, rather than one satisfying each.
      const order = {
        'items': [
          {'sku': 'a', 'qty': 1},
          {'sku': 'b', 'qty': 9},
        ],
      };

      expect(
        matches({
          'items': {
            r'$elemMatch': {'sku': 'a', 'qty': 1},
          },
        }, order),
        isTrue,
      );
      expect(
        matches({
          'items': {
            r'$elemMatch': {'sku': 'a', 'qty': 9},
          },
        }, order),
        isFalse,
        reason: 'no single item is both a and 9',
      );
    });

    test(r'$elemMatch over a list of scalars', () {
      expect(
        matches(
          {
            'scores': {
              r'$elemMatch': {r'$gte': 80},
            },
          },
          {
            'scores': [10, 90],
          },
        ),
        isTrue,
      );
    });
  });

  group('what the default set deliberately lacks', () {
    test(r'$or is not available, and says so', () {
      // CASL's default has no top-level operators at all. Quietly ignoring one
      // would turn a restrictive rule into a permissive one.
      expect(
        () => matches(
          {
            r'$or': [
              {'a': 1},
            ],
          },
          {'a': 1},
        ),
        throwsA(isA<ConditionFormatException>()),
      );
    });

    test('but the table is extensible', () {
      final parser = const MongoQueryParser().withOperators({
        r'$or': (call) => CompoundCondition('or', [
          for (final query in call.value! as List<Object?>)
            call.parser.parse(query! as Map<String, Object?>),
        ]),
      });

      final match = MongoConditionsMatch(
        {
          r'$or': [
            {'a': 1},
            {'b': 2},
          ],
        },
        parser: parser,
      );

      expect(match.matches({'b': 2}), isTrue);
      expect(match.matches({'c': 3}), isFalse);
    });

    test('a stray key beside operators is named in the error', () {
      expect(
        () => matches(
          {
            'a': {r'$gt': 1, 'stray': 2},
          },
          {'a': 5},
        ),
        throwsA(
          isA<ConditionFormatException>().having(
            (e) => e.operator,
            'operator',
            'stray',
          ),
        ),
      );
    });
  });

  group('matching a model directly', () {
    test('a CaslRecord needs no conversion to a map', () {
      expect(matches({'authorId': 7}, _Article(authorId: 7)), isTrue);
      expect(matches({'authorId': 8}, _Article(authorId: 7)), isFalse);
    });

    test('anything else reads as having no fields', () {
      expect(matches({'authorId': 7}, 'a string'), isFalse);
    });
  });

  group('as an ability', () {
    test('createMongoAbility puts it all together', () {
      final ability = createMongoAbility([
        RawRule.of(action: 'read', subject: 'Article'),
        RawRule.of(
          action: 'update',
          subject: 'Article',
          conditions: const {'authorId': 7},
        ),
      ]);

      expect(ability.can('read', _Article(authorId: 1)), isTrue);
      expect(ability.can('update', _Article(authorId: 7)), isTrue);
      expect(ability.can('update', _Article(authorId: 1)), isFalse);
    });

    test('an unconditional forbidding rule can still deny a whole type', () {
      // `matchesEverything` is what allows this, and only this: a rule with no
      // restrictions really does apply to every instance.
      final ability = createMongoAbility([
        RawRule.of(action: 'read', subject: 'Article'),
        RawRule.of(action: 'read', subject: 'Article', inverted: true),
      ]);

      expect(ability.can('read', 'Article'), isFalse);
    });

    test('conditions travel unchanged from a CASL.js payload', () {
      // The shape a server actually sends, parsed by RawRule.fromJson.
      final rule = RawRule.fromJson(const {
        'action': ['read', 'update'],
        'subject': 'Article',
        'conditions': {
          'authorId': 7,
          'status': {
            r'$in': ['draft', 'review'],
          },
        },
      });
      final ability = createMongoAbility([rule]);

      expect(
        ability.can(
          'update',
          subject('Article', const {
            'authorId': 7,
            'status': 'draft',
          }),
        ),
        isTrue,
      );
      expect(
        ability.can(
          'update',
          subject('Article', const {
            'authorId': 7,
            'status': 'published',
          }),
        ),
        isFalse,
      );
    });
  });
}

class _Article with CaslSubject, CaslRecord {
  _Article({required this.authorId});

  final int authorId;

  @override
  String get caslSubjectType => 'Article';

  @override
  Object? caslField(String name) => switch (name) {
    'authorId' => authorId,
    _ => null,
  };
}
