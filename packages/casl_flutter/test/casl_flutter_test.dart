import 'package:casl_flutter/casl_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Ability abilityOf(List<RawRule> rules) => createMongoAbility(rules);

  Widget wrap(Ability ability, Widget child) => AbilityProvider(
    ability: ability,
    child: Directionality(textDirection: TextDirection.ltr, child: child),
  );

  group('Can', () {
    testWidgets('shows its child when permitted', (tester) async {
      await tester.pumpWidget(
        wrap(
          abilityOf([RawRule.of(action: 'read', subject: 'Article')]),
          const Can('read', 'Article', child: Text('visible')),
        ),
      );

      expect(find.text('visible'), findsOneWidget);
    });

    testWidgets('shows nothing when not', (tester) async {
      await tester.pumpWidget(
        wrap(
          abilityOf(const []),
          const Can('read', 'Article', child: Text('visible')),
        ),
      );

      expect(find.text('visible'), findsNothing);
    });

    testWidgets('shows the alternative instead, when given one', (
      tester,
    ) async {
      // Because a control that simply vanishes is one the user cannot ask
      // about — see the widget's own documentation.
      await tester.pumpWidget(
        wrap(
          abilityOf(const []),
          const Can(
            'read',
            'Article',
            otherwise: Text('ask an administrator'),
            child: Text('visible'),
          ),
        ),
      );

      expect(find.text('ask an administrator'), findsOneWidget);
    });

    testWidgets('asks about an instance, not just a type', (tester) async {
      final ability = abilityOf([
        RawRule.of(
          action: 'update',
          subject: 'Article',
          conditions: const {'authorId': 7},
        ),
      ]);

      await tester.pumpWidget(
        wrap(
          ability,
          Column(
            children: [
              Can(
                'update',
                subject('Article', const {'authorId': 7}),
                child: const Text('mine'),
              ),
              Can(
                'update',
                subject('Article', const {'authorId': 8}),
                child: const Text('theirs'),
              ),
            ],
          ),
        ),
      );

      expect(find.text('mine'), findsOneWidget);
      expect(find.text('theirs'), findsNothing);
    });

    testWidgets('narrows to one field when asked to', (tester) async {
      final ability = abilityOf([
        RawRule.of(
          action: 'update',
          subject: 'Article',
          fields: const ['title'],
        ),
      ]);

      await tester.pumpWidget(
        wrap(
          ability,
          const Column(
            children: [
              Can('update', 'Article', field: 'title', child: Text('title')),
              Can('update', 'Article', field: 'body', child: Text('body')),
            ],
          ),
        ),
      );

      expect(find.text('title'), findsOneWidget);
      expect(find.text('body'), findsNothing);
    });
  });

  group('Can.not', () {
    testWidgets('inverts the question', (tester) async {
      // For copy that only makes sense to someone who cannot do the thing —
      // an upgrade prompt, a read-only badge. Written the other way round it
      // would put the real content in `otherwise` and read backwards.
      await tester.pumpWidget(
        wrap(
          abilityOf(const []),
          const Can(
            'invite',
            'User',
            not: true,
            child: Text('Ask an administrator'),
          ),
        ),
      );

      expect(find.text('Ask an administrator'), findsOneWidget);
    });

    testWidgets('and hides once the action becomes permitted', (tester) async {
      final ability = abilityOf(const []);
      await tester.pumpWidget(
        wrap(
          ability,
          const Can('invite', 'User', not: true, child: Text('upgrade')),
        ),
      );
      expect(find.text('upgrade'), findsOneWidget);

      ability.update([RawRule.of(action: 'invite', subject: 'User')]);
      await tester.pump();

      expect(find.text('upgrade'), findsNothing);
    });
  });

  group('CanBuilder', () {
    testWidgets('keeps the control and disables it', (tester) async {
      await tester.pumpWidget(
        wrap(
          abilityOf(const []),
          CanBuilder(
            'delete',
            'Article',
            builder: (context, can) => ElevatedButton(
              onPressed: can.allowed ? () {} : null,
              child: const Text('Delete'),
            ),
          ),
        ),
      );

      expect(find.text('Delete'), findsOneWidget);
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
    });
  });

  group('what the builder is told', () {
    testWidgets('the reason, so a disabled control can explain itself', (
      tester,
    ) async {
      late CanResult result;

      await tester.pumpWidget(
        wrap(
          abilityOf([
            RawRule.of(action: 'delete', subject: 'Article'),
            RawRule.of(
              action: 'delete',
              subject: 'Article',
              inverted: true,
              reason: 'published articles are kept',
            ),
          ]),
          CanBuilder(
            'delete',
            'Article',
            builder: (context, can) {
              result = can;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(result.allowed, isFalse);
      expect(result.reason, 'published articles are kept');
      expect(result.refusal, isNotNull);
    });

    testWidgets('and the ability, for a question these widgets do not ask', (
      tester,
    ) async {
      // `permittedFieldsOf` over a form, say — the escape hatch that keeps
      // this package from having to wrap every function in `casl`.
      late List<String> editable;

      await tester.pumpWidget(
        wrap(
          abilityOf([
            RawRule.of(
              action: 'update',
              subject: 'Article',
              fields: const ['title'],
            ),
          ]),
          CanBuilder(
            'update',
            'Article',
            builder: (context, can) {
              editable = permittedFieldsOf(
                can.ability,
                'update',
                'Article',
                allFields: const ['title', 'body'],
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(editable, ['title']);
    });

    testWidgets('nothing to explain when it is allowed', (tester) async {
      late CanResult result;

      await tester.pumpWidget(
        wrap(
          abilityOf([RawRule.of(action: 'read', subject: 'Article')]),
          CanBuilder(
            'read',
            'Article',
            builder: (context, can) {
              result = can;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(result.allowed, isTrue);
      expect(result.reason, isNull);
    });
  });

  group('rules changing under a running app', () {
    testWidgets('a granted permission appears without navigating', (
      tester,
    ) async {
      // The reason the provider listens at all. A role change arrives on a
      // token refresh, and the screen the user is looking at has to follow.
      final ability = abilityOf(const []);
      await tester.pumpWidget(
        wrap(ability, const Can('read', 'Article', child: Text('visible'))),
      );
      expect(find.text('visible'), findsNothing);

      ability.update([RawRule.of(action: 'read', subject: 'Article')]);
      await tester.pump();

      expect(find.text('visible'), findsOneWidget);
    });

    testWidgets('and a revoked one disappears', (tester) async {
      final ability = abilityOf([
        RawRule.of(action: 'read', subject: 'Article'),
      ]);
      await tester.pumpWidget(
        wrap(ability, const Can('read', 'Article', child: Text('visible'))),
      );
      expect(find.text('visible'), findsOneWidget);

      ability.update([]);
      await tester.pump();

      expect(find.text('visible'), findsNothing);
    });

    testWidgets('swapping the ability itself works too', (tester) async {
      // Signing in as somebody else replaces the object rather than its rules.
      await tester.pumpWidget(
        wrap(
          abilityOf(const []),
          const Can('read', 'Article', child: Text('visible')),
        ),
      );
      expect(find.text('visible'), findsNothing);

      await tester.pumpWidget(
        wrap(
          abilityOf([RawRule.of(action: 'read', subject: 'Article')]),
          const Can('read', 'Article', child: Text('visible')),
        ),
      );

      expect(find.text('visible'), findsOneWidget);
    });

    testWidgets('a disposed subtree stops listening', (tester) async {
      // Rules arrive from a websocket or a refresh, which does not know what
      // is still on screen.
      final ability = abilityOf(const []);
      await tester.pumpWidget(
        wrap(ability, const Can('read', 'Article', child: Text('visible'))),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      ability.update([RawRule.of(action: 'read', subject: 'Article')]);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('the context extensions', () {
    testWidgets('can and cannot answer from anywhere below', (tester) async {
      late bool mayRead;
      late bool mayDelete;

      await tester.pumpWidget(
        wrap(
          abilityOf([RawRule.of(action: 'read', subject: 'Article')]),
          Builder(
            builder: (context) {
              mayRead = context.can('read', 'Article');
              mayDelete = context.cannot('delete', 'Article');
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(mayRead, isTrue);
      expect(mayDelete, isTrue);
    });

    testWidgets('forbidden carries the reason the rule gave', (tester) async {
      // What turns a greyed-out button into one that says why.
      late ForbiddenError? refusal;

      await tester.pumpWidget(
        wrap(
          abilityOf([
            RawRule.of(action: 'delete', subject: 'Article'),
            RawRule.of(
              action: 'delete',
              subject: 'Article',
              inverted: true,
              reason: 'published articles are kept',
            ),
          ]),
          Builder(
            builder: (context) {
              refusal = context.forbidden('delete', 'Article');
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(refusal?.message, 'published articles are kept');
    });

    testWidgets('missing a provider says so, loudly', (tester) async {
      // Answering "no" would be indistinguishable from a real refusal, and one
      // of those is a bug while the other is a support ticket.
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            context.can('read', 'Article');
            return const SizedBox.shrink();
          },
        ),
      );

      expect(
        tester.takeException(),
        isA<FlutterError>().having(
          (e) => e.message,
          'message',
          contains('No AbilityProvider'),
        ),
      );
    });

    testWidgets('maybeOf answers null instead', (tester) async {
      // For a widget used both inside a signed-in shell and outside one.
      late Ability? ability;

      await tester.pumpWidget(
        Builder(
          builder: (context) {
            ability = AbilityProvider.maybeOf(context);
            return const SizedBox.shrink();
          },
        ),
      );

      expect(ability, isNull);
    });

    testWidgets('readAbility does not subscribe', (tester) async {
      // A tap does not need the widget to redraw when the answer changes,
      // because by then the tap is over.
      final ability = abilityOf(const []);
      var builds = 0;

      await tester.pumpWidget(
        wrap(
          ability,
          Builder(
            builder: (context) {
              builds++;
              context.readAbility();
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(builds, 1);

      ability.update([RawRule.of(action: 'read', subject: 'Article')]);
      await tester.pump();

      expect(builds, 1, reason: 'nothing subscribed, so nothing rebuilt');
    });
  });
}
