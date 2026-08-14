// Measures line coverage per package and fails below a floor.
//
//   dart pub global activate coverage
//   dart run tool/coverage/check.dart
//
// The floor is the point of this, not the number. A coverage percentage is a
// weak signal on its own — a suite can touch every line and assert nothing —
// so it is set just under what the suite already achieves. It is there to catch
// a change that adds a hundred lines and no tests, and nothing more. The
// assurance comes from the parity fixtures, the fuzzer and the analyzer.
// ignore_for_file: avoid_print
import 'dart:io';

/// Packages that have tests, and how to run them.
const _packages = <String, ({String root, bool flutter, double floor})>{
  'casl': (root: 'packages/casl', flutter: false, floor: 90),
  'casl_flutter': (root: 'packages/casl_flutter', flutter: true, floor: 85),
  'flutter_onboarding': (
    root: 'packages/flutter_onboarding',
    flutter: true,
    floor: 40,
  ),
};

Future<void> main() async {
  var failed = false;

  for (final entry in _packages.entries) {
    final name = entry.key;
    final package = entry.value;
    stdout.write('${name.padRight(20)} ');

    final lcov = File('${package.root}/coverage/lcov.info');
    if (lcov.existsSync()) lcov.deleteSync();

    final run = package.flutter
        ? await Process.run(
            'flutter',
            const [
              'test',
              '--coverage',
            ],
            workingDirectory: package.root,
          )
        : await _dartCoverage(package.root);

    if (run.exitCode != 0) {
      print('tests failed');
      print('${run.stdout}${run.stderr}');
      failed = true;
      continue;
    }

    if (!lcov.existsSync()) {
      print('no coverage produced');
      failed = true;
      continue;
    }

    final percent = _linePercentOf(lcov.readAsLinesSync());
    final ok = percent >= package.floor;
    print(
      '${percent.toStringAsFixed(1)}%'.padLeft(6) +
          (ok ? '  ✓' : '  ✗ below ${package.floor}%'),
    );
    if (!ok) failed = true;
  }

  if (failed) {
    print('\nCoverage is below the floor. Either add the tests, or move the '
        'floor in tool/coverage/check.dart and say why in the commit.');
    exitCode = 1;
  }
}

/// `dart test --coverage` writes JSON, which `package:coverage` turns into
/// lcov. Flutter's runner does both in one step.
Future<ProcessResult> _dartCoverage(String root) async {
  final tests = await Process.run(
    'dart',
    const [
      'test',
      '--coverage=coverage',
    ],
    workingDirectory: root,
  );
  if (tests.exitCode != 0) return tests;

  return Process.run(
    'dart',
    const [
      'pub',
      'global',
      'run',
      'coverage:format_coverage',
      '--lcov',
      '--in=coverage',
      '--out=coverage/lcov.info',
      '--report-on=lib',
    ],
    workingDirectory: root,
  );
}

/// Lines hit over lines found, from the `LH:` and `LF:` records lcov emits per
/// file.
double _linePercentOf(List<String> lcov) {
  var found = 0;
  var hit = 0;

  for (final line in lcov) {
    if (line.startsWith('LF:')) found += int.parse(line.substring(3));
    if (line.startsWith('LH:')) hit += int.parse(line.substring(3));
  }

  return found == 0 ? 0 : hit / found * 100;
}
