import 'package:flutter/material.dart';
import 'package:flutter_onboarding/flutter_onboarding.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The behaviour that makes this a *one-time* onboarding rather than a
/// carousel: what it shows, when it stops showing, and who is told.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final pages = [
    IntroModel(
      title: const Text('First'),
      description: const Text('The first page'),
      image: const Icon(Icons.looks_one),
    ),
    IntroModel(
      title: const Text('Second'),
      description: const Text('The second page'),
      image: const Icon(Icons.looks_two),
    ),
  ];

  Future<void> pump(
    WidgetTester tester, {
    required VoidCallback onDone,
    bool shouldUseDefaultStorage = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FlutterOnBoarding(
          pages: pages,
          onDone: onDone,
          shouldUseDefaultStorage: shouldUseDefaultStorage,
        ),
      ),
    );
    // Bounded pumps, not pumpAndSettle: the loading state is a spinner, which
    // schedules frames forever and never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Taps a control and lets the page animation finish.
  Future<void> tapAndSettle(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('shows the first page once the stored flag has been read', (
    tester,
  ) async {
    await pump(tester, onDone: () {});

    expect(find.text('First'), findsOneWidget);
    expect(find.text('The first page'), findsOneWidget);
  });

  testWidgets('skips straight to done when it has been seen before', (
    tester,
  ) async {
    // The whole point of the package: a second launch must not show it.
    SharedPreferences.setMockInitialValues({'isDone': true});
    var done = false;

    await pump(tester, onDone: () => done = true);

    expect(done, isTrue);
    expect(find.text('First'), findsNothing);
  });

  testWidgets('Skip jumps to the last page rather than finishing', (
    tester,
  ) async {
    // Worth pinning, because the name suggests otherwise: Skip is a shortcut
    // *through* the pages, not out of them. Only Done completes the flow, so
    // the last page always gets seen.
    var done = false;
    await pump(tester, onDone: () => done = true);

    await tapAndSettle(tester, 'Skip');

    expect(done, isFalse);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Skip'), findsNothing);
  });

  testWidgets('Next advances one page at a time', (tester) async {
    await pump(tester, onDone: () {});

    await tapAndSettle(tester, 'Next');

    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('Done reports completion and records it', (tester) async {
    var done = false;
    await pump(tester, onDone: () => done = true);

    await tapAndSettle(tester, 'Skip');
    await tapAndSettle(tester, 'Done');

    expect(done, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('isDone'), isTrue);
  });

  testWidgets('records nothing when the app owns that decision', (
    tester,
  ) async {
    // shouldUseDefaultStorage: false means the caller stores it. Writing the
    // flag anyway would make the intro unreachable for an app that keys it per
    // account — and the callback must still fire, or nothing happens at all.
    var done = false;
    await pump(
      tester,
      onDone: () => done = true,
      shouldUseDefaultStorage: false,
    );

    await tapAndSettle(tester, 'Skip');
    await tapAndSettle(tester, 'Done');

    expect(done, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('isDone'), isNull);
  });
}
