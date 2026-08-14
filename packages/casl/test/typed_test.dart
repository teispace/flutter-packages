// Typed abilities: the point of which is a *compile* error, so half of this
// file asserts what the analyzer says rather than what the code does.
//
// The mechanism is extension types over `String`. They erase completely, so a
// typed action IS a string at runtime — nothing changes on the wire, nothing
// is converted per call, and rules from a server need no adaptation. What
// changes is only what the analyzer will let you write.
import 'dart:io';

import 'package:casl/casl.dart';
import 'package:test/test.dart';

/// An application's vocabulary. Declared once; used everywhere.
extension type const AppAction(String wire) implements String {
  static const read = AppAction('read');
  static const create = AppAction('create');
  static const update = AppAction('update');
  static const delete = AppAction('delete');
  static const manage = AppAction('manage');

  /// Every action, for a screen that lists them. Extension types have no
  /// `values` of their own, so this is the substitute — and unlike an enum's,
  /// it costs nothing at runtime.
  static const values = <AppAction>[read, create, update, delete, manage];
}

extension type const AppSubject(String wire) implements String {
  static const article = AppSubject('Article');
  static const user = AppSubject('User');
  static const all = AppSubject('all');
}

typedef AppAbility = Ability<AppAction, AppSubject>;

void main() {
  group('what the analyzer refuses', () {
    late String output;

    setUpAll(() async {
      final result = await Process.run('dart', [
        'analyze',
        'test/type_safety/must_not_compile.dart',
      ]);
      output = '${result.stdout}${result.stderr}';
    });

    test('a raw string where an action is wanted', () {
      expect(
        output,
        contains(
          "The argument type 'String' can't be assigned to the parameter "
          "type 'AppAction'",
        ),
      );
    });

    test("another vocabulary's action of the same name", () {
      // `OtherAction('read')` and `AppAction('read')` are the same string at
      // runtime and different types at compile time, which is the whole trick.
      expect(
        output,
        contains(
          "The argument type 'OtherAction' can't be assigned to the parameter "
          "type 'AppAction'",
        ),
      );
    });

    test('a raw string where a subject type is wanted', () {
      expect(
        output,
        contains(
          "The argument type 'String' can't be assigned to the parameter "
          "type 'AppSubject'",
        ),
      );
    });

    test('and on the builder too, not only on checks', () {
      expect(
        output,
        contains(
          "The argument type 'String' can't be assigned to the parameter "
          "type 'AppSubject?'",
        ),
      );
    });
  });

  group('what it answers', () {
    test('identically to the untyped form', () {
      final typed = build();
      final untyped = defineAbility((can, cannot) {
        can('read', 'Article');
        can.each(const ['update', 'delete'], 'Article', {'authorId': 7});
        cannot('delete', 'Article', {
          'published': true,
        }).because('a published article cannot be deleted');
      });

      final mine = subject('Article', const {'authorId': 7});
      final published = subject(
        'Article',
        const {'authorId': 7, 'published': true},
      );

      expect(typed.can(AppAction.read, AppSubject.article), isTrue);
      expect(
        typed.can(AppAction.read, AppSubject.article),
        untyped.can('read', 'Article'),
      );
      expect(typed.can(AppAction.update, mine), untyped.can('update', mine));
      expect(
        typed.can(AppAction.delete, published),
        untyped.can('delete', published),
      );
    });

    test('actionsFor comes back in the vocabulary', () {
      final actions = build().actionsFor(AppSubject.article);

      expect(actions, isA<Set<AppAction>>());
      expect(actions, contains(AppAction.update));
    });

    test('reasons survive', () {
      final refusal = build().errorUnlessCan(
        AppAction.delete,
        subject('Article', const {'authorId': 7, 'published': true}),
      );

      expect(refusal?.message, 'a published article cannot be deleted');
    });

    test('the guard extension is typed too', () {
      final ability = build();

      expect(
        () => ForbiddenError.from(ability).throwUnlessCan(AppAction.create),
        throwsA(isA<ForbiddenError>()),
      );
    });

    test('so are the extras', () {
      final ability = defineAbility<AppAction, AppSubject>(
        (can, _) => can(AppAction.create, AppSubject.article, {
          'status': 'draft',
        }),
      );

      expect(
        rulesToFields(ability, AppAction.create, AppSubject.article),
        {'status': 'draft'},
      );
      expect(
        rulesToAst(ability, AppAction.create, AppSubject.article),
        isA<FieldCondition>(),
      );
      expect(
        permittedFieldsOf(
          ability,
          AppAction.create,
          AppSubject.article,
          allFields: const ['status', 'title'],
        ),
        ['status', 'title'],
      );
    });
  });

  group('what it costs', () {
    test('nothing on the wire — a typed action is a string', () {
      expect(AppAction.read, 'read');
      expect(AppAction.read.runtimeType, String);
      expect(identical(AppAction.read.wire, 'read'), isTrue);
    });

    test('nothing to adopt rules from a server', () {
      // The cast is a no-op: `List<String>` and `List<AppAction>` are the same
      // list. A rule format that needed converting would be a rule format that
      // could drift.
      final fromServer = unpackRules(const [
        ['read,update', 'Article'],
      ]);
      final ability = createMongoAbility<AppAction, AppSubject>(fromServer);

      expect(ability.can(AppAction.read, AppSubject.article), isTrue);
      expect(ability.rules.first.actions, ['read', 'update']);
    });

    test('an action the vocabulary has never heard of still evaluates', () {
      // A client is routinely older than its server. A rule mentioning an
      // action this build does not declare must still index and still deny —
      // it must not be droppable, and it must not throw.
      final ability = createMongoAbility<AppAction, AppSubject>([
        RawRule.of(action: 'archive', subject: 'Article'),
      ]);

      expect(ability.can(AppAction.read, AppSubject.article), isFalse);
      expect(
        ability.actionsFor(AppSubject.article),
        contains(const AppAction('archive')),
      );
    });

    test('one shape of typing, given up on purpose', () {
      // `RuleAdder.each` takes `List<String>`, not `List<A>`. This test exists
      // so nobody "fixes" that: with `List<A>`, an inline list literal inside
      // an *inferred* `defineAbility` reifies as `List<Object?>` — because the
      // lambda body is analysed before `A` is known — and throws at the runtime
      // parameter check. Every line below would crash.
      expect(
        () => defineAbility((can, cannot) {
          can.each(['update', 'delete'], 'Article');
          cannot.each(const ['read'], 'Article');
        }),
        returnsNormally,
      );

      // And a `List<A>` still passes, so nothing is lost when you have one.
      expect(
        () => defineAbility<AppAction, AppSubject>(
          (can, _) => can.each(const [AppAction.read, AppAction.update]),
        ),
        returnsNormally,
      );
    });

    test('nothing at the boundary — a typed ability is an untyped one', () {
      // Covariance, and the reason `ForbiddenError.ability` and everything in
      // `casl_flutter` can stay unparameterised.
      expect(asUntyped(build()).can('read', 'Article'), isTrue);
    });
  });
}

/// The ability every group here asks questions of.
AppAbility build() => defineAbility<AppAction, AppSubject>((can, cannot) {
  can(AppAction.read, AppSubject.article);
  can.each(
    const [AppAction.update, AppAction.delete],
    AppSubject.article,
    {'authorId': 7},
  );
  cannot(AppAction.delete, AppSubject.article, {
    'published': true,
  }).because('a published article cannot be deleted');
});

/// Takes a typed ability where an untyped one is wanted. Compiles only because
/// `AppAction` is a subtype of `String`, which is what makes every
/// unparameterised part of the API — and all of `casl_flutter` — keep working.
Ability asUntyped(Ability ability) => ability;
