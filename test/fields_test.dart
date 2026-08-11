import 'package:casl/casl.dart';
import 'package:test/test.dart';

void main() {
  bool Function(String) matcher(List<String> patterns) =>
      fieldPatternMatcher(patterns);

  group('patterns without a star', () {
    test('are an exact list, and skip regular expressions entirely', () {
      final matches = matcher(['title', 'body']);

      expect(matches('title'), isTrue);
      expect(matches('body'), isTrue);
      expect(matches('titles'), isFalse);
      expect(matches('title.sub'), isFalse);
    });
  });

  group('a single star stays inside one segment', () {
    test('address.* covers the parts of an address', () {
      final matches = matcher(['address.*']);

      expect(matches('address.city'), isTrue);
      expect(matches('address.street'), isTrue);
      expect(
        matches('address.geo.lat'),
        isFalse,
        reason: 'one star does not cross a dot',
      );
      expect(matches('title'), isFalse);
    });

    test('and covers the address itself', () {
      // A rule about the parts of a thing is taken to be a rule about the
      // thing. Surprising until you write `can('read','User',['address.*'])`
      // and find `address` itself excluded from what you may read.
      expect(matcher(['address.*'])('address'), isTrue);
    });

    test('a bare star is any one segment', () {
      final matches = matcher(['*']);

      expect(matches('title'), isTrue);
      expect(matches('address'), isTrue);
      expect(matches('address.city'), isFalse);
    });

    test('between two dots it must consume a whole segment', () {
      final matches = matcher(['a.*.c']);

      expect(matches('a.b.c'), isTrue);
      expect(matches('a.c'), isFalse, reason: 'the middle cannot be empty');
      expect(matches('a.b.b.c'), isFalse);
    });
  });

  group('two stars cross segments', () {
    test('address.** covers everything below an address', () {
      final matches = matcher(['address.**']);

      expect(matches('address'), isTrue);
      expect(matches('address.city'), isTrue);
      expect(matches('address.geo.lat'), isTrue);
      expect(matches('title'), isFalse);
    });

    test('a bare double star is everything', () {
      final matches = matcher(['**']);

      expect(matches('title'), isTrue);
      expect(matches('address.geo.lat'), isTrue);
    });
  });

  group('several patterns', () {
    test('any one of them is enough', () {
      final matches = matcher(['title', 'address.*']);

      expect(matches('title'), isTrue);
      expect(matches('address.city'), isTrue);
      expect(matches('body'), isFalse);
    });
  });

  group('characters a regular expression would misread', () {
    test('are escaped, so a dot is a dot', () {
      // Without escaping, `a.b` would match `axb` — quietly permitting a field
      // nobody named.
      final matches = matcher(['a.b']);

      expect(matches('a.b'), isTrue);
      expect(matches('axb'), isFalse);
    });

    test('and so are the rest of them', () {
      final matches = matcher(['we+ird(name)', r'price$usd']);

      expect(matches('we+ird(name)'), isTrue);
      expect(matches('weeeird(name)'), isFalse);
      expect(matches(r'price$usd'), isTrue);
    });
  });

  group('a rule restricted to fields', () {
    final ability = Ability([
      RawRule.of(action: 'read', subject: 'Article'),
      RawRule.of(action: 'update', subject: 'Article', fields: const ['title']),
    ]);

    test('permits the named field', () {
      expect(ability.can('update', 'Article', 'title'), isTrue);
    });

    test('and refuses the others', () {
      expect(ability.can('update', 'Article', 'body'), isFalse);
    });

    test('asking about no field asks whether ANY field is permitted', () {
      // What a screen asks before rendering an edit button at all.
      expect(ability.can('update', 'Article'), isTrue);
    });

    test('a rule with no fields covers all of them', () {
      expect(ability.can('read', 'Article', 'anything'), isTrue);
    });

    test('a forbidding rule does not answer the "any field" question', () {
      // It takes a field away rather than granting one, so letting it match
      // here would end the search at a rule that never permits anything.
      final restricted = Ability([
        RawRule.of(action: 'update', subject: 'Article'),
        RawRule.of(
          action: 'update',
          subject: 'Article',
          fields: const ['secret'],
          inverted: true,
        ),
      ]);

      expect(restricted.can('update', 'Article'), isTrue);
      expect(restricted.can('update', 'Article', 'secret'), isFalse);
      expect(restricted.can('update', 'Article', 'title'), isTrue);
    });
  });

  group('permittedFieldsOf', () {
    const allFields = ['title', 'body', 'published', 'authorId'];

    test('lists everything when a rule names no fields', () {
      final ability = Ability([
        RawRule.of(action: 'update', subject: 'Article'),
      ]);

      expect(
        permittedFieldsOf(ability, 'update', 'Article', allFields: allFields),
        allFields,
      );
    });

    test('narrows to what the rules name', () {
      final ability = Ability([
        RawRule.of(
          action: 'update',
          subject: 'Article',
          fields: const ['title', 'body'],
        ),
      ]);

      expect(
        permittedFieldsOf(ability, 'update', 'Article', allFields: allFields),
        ['title', 'body'],
      );
    });

    test('a later forbidding rule takes fields back', () {
      // The reason this cannot be answered field by field: `can(...,'body')`
      // is right about each one, but building the list needs the ordering.
      final ability = Ability([
        RawRule.of(action: 'update', subject: 'Article'),
        RawRule.of(
          action: 'update',
          subject: 'Article',
          fields: const ['published', 'authorId'],
          inverted: true,
        ),
      ]);

      expect(
        permittedFieldsOf(ability, 'update', 'Article', allFields: allFields),
        ['title', 'body'],
      );
    });

    test('and a later permitting rule gives them back again', () {
      final ability = Ability([
        RawRule.of(action: 'update', subject: 'Article'),
        RawRule.of(
          action: 'update',
          subject: 'Article',
          fields: const ['published'],
          inverted: true,
        ),
        RawRule.of(
          action: 'update',
          subject: 'Article',
          fields: const ['published'],
        ),
      ]);

      expect(
        permittedFieldsOf(ability, 'update', 'Article', allFields: allFields),
        contains('published'),
      );
    });

    test('patterns are resolved against the real field names', () {
      // A rule says `address.*`; a form needs `address.city`.
      final ability = Ability([
        RawRule.of(
          action: 'read',
          subject: 'User',
          fields: const ['address.*'],
        ),
      ]);

      expect(
        permittedFieldsOf(
          ability,
          'read',
          'User',
          allFields: const ['name', 'address.city', 'address.geo.lat'],
        ),
        ['address.city'],
      );
    });

    test("the order is the caller's, not the rules'", () {
      // This drives a form, and field order is a design decision rather than
      // an accident of how the rules were written.
      final ability = Ability([
        RawRule.of(
          action: 'update',
          subject: 'Article',
          fields: const ['published', 'title'],
        ),
      ]);

      expect(
        permittedFieldsOf(ability, 'update', 'Article', allFields: allFields),
        ['title', 'published'],
      );
    });

    test('conditions are honoured against an instance', () {
      final ability = createMongoAbility([
        RawRule.of(
          action: 'update',
          subject: 'Article',
          conditions: const {'authorId': 7},
          fields: const ['title'],
        ),
      ]);

      expect(
        permittedFieldsOf(
          ability,
          'update',
          subject('Article', const {'authorId': 7}),
          allFields: allFields,
        ),
        ['title'],
      );
      expect(
        permittedFieldsOf(
          ability,
          'update',
          subject('Article', const {'authorId': 8}),
          allFields: allFields,
        ),
        isEmpty,
      );
    });
  });

  group('rulesToFields', () {
    test('turns conditions into a starting object', () {
      // So a user who may only create drafts gets a form that already says
      // draft, rather than one that lets them choose and then refuses.
      final ability = createMongoAbility([
        RawRule.of(
          action: 'create',
          subject: 'Article',
          conditions: const {'status': 'draft', 'authorId': 7},
        ),
      ]);

      expect(rulesToFields(ability, 'create', 'Article'), {
        'status': 'draft',
        'authorId': 7,
      });
    });

    test('skips operator queries, which are ranges rather than values', () {
      final ability = createMongoAbility([
        RawRule.of(
          action: 'create',
          subject: 'Article',
          conditions: const {
            'status': 'draft',
            'views': {r'$gte': 100},
          },
        ),
      ]);

      expect(rulesToFields(ability, 'create', 'Article'), {'status': 'draft'});
    });

    test('skips forbidding rules, which say what is not allowed', () {
      final ability = createMongoAbility([
        RawRule.of(
          action: 'create',
          subject: 'Article',
          conditions: const {'status': 'draft'},
        ),
        RawRule.of(
          action: 'create',
          subject: 'Article',
          conditions: const {'status': 'published'},
          inverted: true,
        ),
      ]);

      expect(rulesToFields(ability, 'create', 'Article'), {'status': 'draft'});
    });

    test('nests a dotted condition', () {
      final ability = createMongoAbility([
        RawRule.of(
          action: 'create',
          subject: 'User',
          conditions: const {'address.country': 'NP'},
        ),
      ]);

      expect(rulesToFields(ability, 'create', 'User'), {
        'address': {'country': 'NP'},
      });
    });
  });
}
