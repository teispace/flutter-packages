import 'package:casl/casl.dart';
import 'package:test/test.dart';

/// A model that declares its own subject type, as every model should.
class Article with CaslSubject {
  Article({this.authorId = 1, this.published = false});

  final int authorId;
  final bool published;

  @override
  String get caslSubjectType => 'Article';
}

void main() {
  PureAbility abilityOf(void Function(AbilityBuilder) define) {
    final builder = AbilityBuilder();
    define(builder);
    return builder.build();
  }

  group('the basics', () {
    test('nothing is permitted by default', () {
      // An ability grants. Silence is a refusal, and it has to be — the
      // alternative is a permission system that fails open.
      expect(PureAbility(const []).can('read', 'Article'), isFalse);
    });

    test('a rule permits exactly what it names', () {
      final ability = abilityOf((b) => b.can('read', 'Article'));

      expect(ability.can('read', 'Article'), isTrue);
      expect(ability.can('update', 'Article'), isFalse);
      expect(ability.can('read', 'Comment'), isFalse);
    });

    test('cannot is the exact negation of can', () {
      final ability = abilityOf((b) => b.can('read', 'Article'));

      expect(ability.cannot('read', 'Article'), isFalse);
      expect(ability.cannot('update', 'Article'), isTrue);
    });
  });

  group('precedence — the rule everyone gets wrong', () {
    test('the LAST matching rule wins, not the forbidding one', () {
      // The single most important assertion in this package. A port that
      // implements "any matching cannot forbids" passes every other test here
      // and is wrong in a way that only shows up on layered rule sets.
      final ability = abilityOf(
        (b) => b
          ..cannot('read', 'Article')
          ..can('read', 'Article'),
      );

      expect(
        ability.can('read', 'Article'),
        isTrue,
        reason: 'the later `can` overrides the earlier `cannot`',
      );
    });

    test('and equally the other way round', () {
      final ability = abilityOf(
        (b) => b
          ..can('read', 'Article')
          ..cannot('read', 'Article'),
      );

      expect(ability.can('read', 'Article'), isFalse);
    });

    test('which is what makes a base set overridable', () {
      // The reason the semantics are this way: a role can be layered on top of
      // a default grant and actually take something away, or give it back.
      final ability = abilityOf(
        (b) => b
          ..can('manage', 'all')
          ..cannot('delete', 'Article')
          ..can('delete', 'Article'),
      );

      expect(ability.can('read', 'Comment'), isTrue);
      expect(ability.can('delete', 'Article'), isTrue);
    });
  });

  group('wildcards are just index entries', () {
    test('manage covers every action', () {
      final ability = abilityOf((b) => b.can('manage', 'Article'));

      expect(ability.can('read', 'Article'), isTrue);
      expect(ability.can('anything-at-all', 'Article'), isTrue);
      expect(ability.can('read', 'Comment'), isFalse);
    });

    test('all covers every subject type', () {
      final ability = abilityOf((b) => b.can('read', 'all'));

      expect(ability.can('read', 'Article'), isTrue);
      expect(ability.can('read', 'Comment'), isTrue);
      expect(ability.can('update', 'Article'), isFalse);
    });

    test('manage:all is the administrator, and one rule says it', () {
      // The grant that breaks a naive `Set<String>.contains` implementation:
      // it locks out precisely the account allowed to do everything, and
      // nobody else — so it survives a developer testing as an admin.
      final ability = abilityOf((b) => b.can('manage', 'all'));

      expect(ability.can('read', 'User'), isTrue);
      expect(ability.can('destroy', 'Invoice'), isTrue);
    });

    test('a later specific rule still beats an earlier wildcard', () {
      final ability = abilityOf(
        (b) => b
          ..can('manage', 'all')
          ..cannot('delete', 'Article'),
      );

      expect(ability.can('update', 'Article'), isTrue);
      expect(ability.can('delete', 'Article'), isFalse);
    });

    test('both names are configurable, because they are conventions', () {
      final ability = PureAbility(
        [RawRule.of(action: 'ALL', subject: 'EVERYTHING')],
        anyActionName: 'ALL',
        anySubjectTypeName: 'EVERYTHING',
      );

      expect(ability.can('read', 'Article'), isTrue);
    });
  });

  group('subject types versus instances', () {
    test('a declared subject type survives obfuscation', () {
      // `runtimeType` would be renamed by --obfuscate and stop matching, in
      // release builds only. This is the whole reason CaslSubject exists.
      final ability = abilityOf((b) => b.can('read', 'Article'));

      expect(ability.can('read', Article()), isTrue);
    });

    test('the subject() wrapper types something we do not own', () {
      final ability = abilityOf((b) => b.can('read', 'Article'));

      expect(ability.can('read', subject('Article', {'id': 1})), isTrue);
      expect(ability.can('read', subject('Comment', {'id': 1})), isFalse);
    });

    test('asking about a type is a different question from an instance', () {
      // "Is there any article I may update?" versus "may I update this one?".
      // A menu item asks the first; the button on a row asks the second.
      final ability = PureAbility(
        [
          RawRule.of(
            action: 'update',
            subject: 'Article',
            conditions: const {'authorId': 1},
          ),
        ],
        conditionsMatcher: _equalityMatcher,
      );

      expect(
        ability.can('update', 'Article'),
        isTrue,
        reason: 'some article may be updatable, so do not hide the UI',
      );
      expect(ability.can('update', Article(authorId: 2)), isFalse);
      expect(ability.can('update', Article()), isTrue);
    });

    test('a forbidding rule does not answer for a whole type', () {
      // "You cannot update articles you did not write" must never be read as
      // "you cannot update articles" — that hides the feature from everyone.
      final ability = PureAbility(
        [
          RawRule.of(action: 'update', subject: 'Article'),
          RawRule.of(
            action: 'update',
            subject: 'Article',
            conditions: const {'published': true},
            inverted: true,
          ),
        ],
        conditionsMatcher: _equalityMatcher,
      );

      expect(ability.can('update', 'Article'), isTrue);
      expect(ability.can('update', Article(published: true)), isFalse);
      expect(ability.can('update', Article()), isTrue);
    });
  });

  group('rules with conditions need a matcher', () {
    test('and say so instead of silently matching nothing', () {
      // The failure mode this replaces is the worst kind: a rule that compiles,
      // never matches, and quietly denies.
      expect(
        () => PureAbility([
          RawRule.of(
            action: 'read',
            subject: 'Article',
            conditions: const {'authorId': 1},
          ),
        ]),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('conditionsMatcher'),
          ),
        ),
      );
    });

    test('but field rules work out of the box', () {
      // A deliberate deviation from CASL.js, which requires a field matcher
      // too. A condition language is a real choice; `*` and `**` mean one
      // thing everywhere, so defaulting it cannot change what a rule means —
      // it only replaces a throw with the answer everyone would have supplied.
      final ability = PureAbility([
        RawRule.of(action: 'read', subject: 'Article', fields: 'title'),
      ]);

      expect(ability.can('read', 'Article', 'title'), isTrue);
      expect(ability.can('read', 'Article', 'body'), isFalse);
    });

    test('an empty fields list is a mistake, not "no fields"', () {
      expect(
        () => PureAbility([
          RawRule.of(
            action: 'read',
            subject: 'Article',
            fields: const <String>[],
          ),
        ]),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('reasons', () {
    test('travel with the rule that forbade it', () {
      final builder = AbilityBuilder()..can('delete', 'Article');
      builder
          .cannot('delete', 'Article')
          .because('published articles are kept');

      final rule = builder.build().relevantRuleFor('delete', 'Article');

      expect(rule?.inverted, isTrue);
      expect(rule?.reason, 'published articles are kept');
    });
  });

  group('updating', () {
    test('replaces everything and re-indexes', () {
      final ability = abilityOf((b) => b.can('read', 'Article'))
        ..update([RawRule.of(action: 'read', subject: 'Comment')]);

      expect(ability.can('read', 'Article'), isFalse);
      expect(ability.can('read', 'Comment'), isTrue);
    });

    test('tells listeners before and after', () {
      // The order matters: a cache that has to read the outgoing grant needs
      // `update`, and a UI that redraws needs `updated`.
      final ability = abilityOf((b) => b.can('read', 'Article'));
      final seen = <String>[];

      ability
        ..on(
          'update',
          (_) => seen.add('before:${ability.can('read', 'Article')}'),
        )
        ..on(
          'updated',
          (_) => seen.add('after:${ability.can('read', 'Article')}'),
        )
        ..update([]);

      expect(seen, ['before:true', 'after:false']);
    });

    test('unsubscribing stops the callbacks', () {
      final ability = abilityOf((b) => b.can('read', 'Article'));
      var calls = 0;

      final off = ability.on('updated', (_) => calls++);
      ability.update([]);
      off();
      ability.update([]);

      expect(calls, 1);
    });
  });

  group('actionsFor', () {
    test('lists what is written about a subject type, wildcards included', () {
      final ability = abilityOf(
        (b) => b
          ..can(['read', 'update'], 'Article')
          ..can('audit', 'all'),
      );

      expect(ability.actionsFor('Article'), {'read', 'update', 'audit'});
    });
  });
}

/// A deliberately tiny matcher: every condition must equal the field exactly.
///
/// The real one arrives with the MongoDB operators. These tests are about the
/// *ability*, and using the full matcher here would let a bug in either one
/// hide a bug in the other.
ConditionsMatch Function(Map<String, Object?>) get _equalityMatcher =>
    _EqualityMatch.new;

final class _EqualityMatch implements ConditionsMatch {
  _EqualityMatch(this.conditions);

  final Map<String, Object?> conditions;

  @override
  bool get matchesEverything => conditions.isEmpty;

  @override
  bool matches(Object? subject) {
    if (subject is! Article) return false;
    final fields = {
      'authorId': subject.authorId,
      'published': subject.published,
    };
    return conditions.entries.every((e) => fields[e.key] == e.value);
  }
}
