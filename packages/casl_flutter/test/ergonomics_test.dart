// The Flutter-side findings, each group named for the one it pins.
//
// Three of these are about *when* things happen — during a build, during a
// dispose, during an event — which is where a Flutter binding differs from a
// React one and where the bugs were.
import 'package:casl_flutter/casl_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// One application's vocabulary, as `package:casl` documents declaring it.
extension type const AppAction(String wire) implements String {
  static const read = AppAction('read');
  static const update = AppAction('update');
  static const delete = AppAction('delete');
}

/// Pinning the type argument is what makes a typo stop compiling.
typedef AppCan = Can<AppAction>;
typedef AppCanBuilder = CanBuilder<AppAction>;

/// The three lines an application writes to get the same guarantee from
/// `context`. Extension methods infer their type argument from the call site,
/// so a package-level `context.can<A>(…)` could never reject a raw string —
/// only a concrete parameter type can.
extension AppAbilityContext on BuildContext {
  bool may(AppAction action, [Object? subject, String? field]) =>
      ability.can(action, subject, field);
}

void main() {
  Widget wrap(Ability ability, Widget child) => AbilityProvider(
    ability: ability,
    child: Directionality(textDirection: TextDirection.ltr, child: child),
  );

  group('F-02 · a reason and a message are different things', () {
    final ability = createMongoAbility([
      RawRule.of(action: 'update', subject: 'Article'),
      RawRule.of(
        action: 'update',
        subject: 'Article',
        conditions: const {'locked': true},
        inverted: true,
        reason: 'the article is locked',
      ),
      RawRule.of(action: 'delete', subject: 'Article', inverted: true),
    ]);

    testWidgets('the rule speaks, so reason and message agree', (tester) async {
      late CanResult result;
      await tester.pumpWidget(
        wrap(
          ability,
          CanBuilder(
            'update',
            subject('Article', const {'locked': true}),
            builder: (_, can) {
              result = can;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(result.allowed, isFalse);
      expect(result.reason, 'the article is locked');
      expect(result.message, 'the article is locked');
    });

    testWidgets('the rule says nothing, so reason is null', (tester) async {
      // The bug this fixes: `reason` used to resolve through
      // `ForbiddenError.message`, so it was never null when disallowed — and
      // `Tooltip(message: can.reason ?? '')`, straight out of our own README,
      // always rendered `Cannot execute "delete" on "Article"`.
      late CanResult result;
      await tester.pumpWidget(
        wrap(
          ability,
          CanBuilder(
            'delete',
            'Article',
            builder: (_, can) {
              result = can;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(result.allowed, isFalse);
      expect(result.reason, isNull);
      expect(result.message, 'Cannot execute "delete" on "Article"');
    });

    testWidgets('both are null when permitted', (tester) async {
      late CanResult result;
      await tester.pumpWidget(
        wrap(
          ability,
          CanBuilder(
            'update',
            subject('Article', const {'locked': false}),
            builder: (_, can) {
              result = can;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(result.allowed, isTrue);
      expect(result.reason, isNull);
      expect(result.message, isNull);
      expect(result.refusal, isNull);
    });
  });

  group('F-03 · rules may change during a build', () {
    testWidgets('without setState() called during build', (tester) async {
      // A screen that fetches on its first frame, a locator that initialises
      // lazily, a router redirect — any of them can replace the rules while
      // the tree is being built. Before, that threw.
      final ability = createMongoAbility(const []);

      await tester.pumpWidget(
        wrap(
          ability,
          _UpdatesDuringBuild(
            ability,
            child: const Can('read', 'Article', child: Text('visible')),
          ),
        ),
      );

      expect(
        tester.takeException(),
        isNull,
        reason: 'this threw "setState() called during build" before',
      );
      expect(
        find.text('visible'),
        findsOneWidget,
        reason: 'deferred to the end of the frame, so still the same pump',
      );
    });

    testWidgets('an ordinary update still lands in the same frame', (
      tester,
    ) async {
      final ability = createMongoAbility(const []);
      await tester.pumpWidget(
        wrap(ability, const Can('read', 'Article', child: Text('visible'))),
      );

      expect(find.text('visible'), findsNothing);

      ability.update([RawRule.of(action: 'read', subject: 'Article')]);
      await tester.pump();

      expect(find.text('visible'), findsOneWidget);
    });
  });

  group('F-05 · a provider may be disposed while the ability emits', () {
    testWidgets('unsubscribing mid-event does not throw', (tester) async {
      // The Flutter face of D-04. An update that tears the provider out of the
      // tree disposes it, and disposal unsubscribes — from inside the emit.
      final ability = createMongoAbility(const []);

      await tester.pumpWidget(
        _RemovesProviderOnUpdate(
          ability: ability,
          child: const Can('read', 'Article', child: Text('visible')),
        ),
      );

      expect(find.text('visible'), findsNothing);

      ability.update([RawRule.of(action: 'read', subject: 'Article')]);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('gone'), findsOneWidget);
    });
  });

  group('F-04 · AbilityNotifier', () {
    testWidgets('rebuilds a ListenableBuilder when the rules change', (
      tester,
    ) async {
      final ability = createMongoAbility(const []);
      final notifier = AbilityNotifier(ability);
      addTearDown(notifier.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ListenableBuilder(
            listenable: notifier,
            builder: (_, _) =>
                Text(notifier.can('read', 'Article') ? 'yes' : 'no'),
          ),
        ),
      );

      expect(find.text('no'), findsOneWidget);

      ability.update([RawRule.of(action: 'read', subject: 'Article')]);
      await tester.pump();

      expect(find.text('yes'), findsOneWidget);
    });

    testWidgets('stops listening when disposed, and leaves the ability', (
      tester,
    ) async {
      final ability = createMongoAbility(const []);
      AbilityNotifier(ability).dispose();

      // Notifying a disposed ChangeNotifier throws, so this asserts the
      // unsubscribe happened. The ability itself must be unharmed: it outlives
      // every screen that watches it.
      expect(
        () => ability.update([RawRule.of(action: 'read', subject: 'Article')]),
        returnsNormally,
      );
      expect(ability.can('read', 'Article'), isTrue);
    });

    testWidgets('forwards the reason a rule gave', (tester) async {
      final notifier = AbilityNotifier(
        createMongoAbility([
          RawRule.of(
            action: 'delete',
            subject: 'Article',
            inverted: true,
            reason: 'articles are kept',
          ),
        ]),
      );
      addTearDown(notifier.dispose);

      expect(
        notifier.forbidden('delete', 'Article')?.reason,
        'articles are kept',
      );
      expect(notifier.cannot('delete', 'Article'), isTrue);
    });
  });

  group('typed widgets', () {
    final ability = createMongoAbility<AppAction, String>([
      RawRule.of(action: 'read', subject: 'Article'),
    ]);

    testWidgets('a typedef pins the action type without changing call sites', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          ability,
          const Column(
            children: [
              AppCan(AppAction.read, 'Article', child: Text('visible')),
              AppCan(AppAction.delete, 'Article', child: Text('hidden')),
            ],
          ),
        ),
      );

      expect(find.text('visible'), findsOneWidget);
      expect(find.text('hidden'), findsNothing);
    });

    testWidgets('and the builder form too', (tester) async {
      await tester.pumpWidget(
        wrap(
          ability,
          AppCanBuilder(
            AppAction.read,
            'Article',
            builder: (_, can) => Text(can.allowed ? 'yes' : 'no'),
          ),
        ),
      );

      expect(find.text('yes'), findsOneWidget);
    });

    testWidgets('an application extension types context too', (tester) async {
      await tester.pumpWidget(
        wrap(
          ability,
          Builder(
            builder: (context) =>
                Text(context.may(AppAction.read, 'Article') ? 'yes' : 'no'),
          ),
        ),
      );

      expect(find.text('yes'), findsOneWidget);
    });

    testWidgets('a typed ability is still an untyped one to the provider', (
      tester,
    ) async {
      // Covariance. It is why `AbilityProvider` and `AbilityScope` need no type
      // parameters of their own, and why the untyped widgets keep working in a
      // typed application.
      await tester.pumpWidget(
        wrap(ability, const Can('read', 'Article', child: Text('visible'))),
      );

      expect(find.text('visible'), findsOneWidget);
    });
  });
}

/// Replaces the rules from inside its own `build`.
class _UpdatesDuringBuild extends StatelessWidget {
  const _UpdatesDuringBuild(this.ability, {required this.child});

  final Ability ability;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (ability.rules.isEmpty) {
      ability.update([RawRule.of(action: 'read', subject: 'Article')]);
    }
    return child;
  }
}

/// Tears the provider out of the tree when the rules change, so the provider is
/// disposed — and unsubscribes — from inside the ability's own event.
class _RemovesProviderOnUpdate extends StatefulWidget {
  const _RemovesProviderOnUpdate({required this.ability, required this.child});

  final Ability ability;
  final Widget child;

  @override
  State<_RemovesProviderOnUpdate> createState() =>
      _RemovesProviderOnUpdateState();
}

class _RemovesProviderOnUpdateState extends State<_RemovesProviderOnUpdate> {
  late final Unsubscribe _off;
  bool _removed = false;

  @override
  void initState() {
    super.initState();
    _off = widget.ability.on('updated', (_) {
      if (mounted) setState(() => _removed = true);
    });
  }

  @override
  void dispose() {
    _off();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: _removed
        ? const Text('gone')
        : AbilityProvider(ability: widget.ability, child: widget.child),
  );
}
