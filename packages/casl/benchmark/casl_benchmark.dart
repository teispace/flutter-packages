// Measures the three things a permission check actually costs, so claims about
// performance in the README are numbers rather than adjectives.
//
//   dart run benchmark/casl_benchmark.dart
//
// Deliberately no `benchmark_harness` dependency: this package depends on
// `meta` and nothing else, and a dev dependency that only a maintainer runs is
// still a dependency somebody has to resolve.
// ignore_for_file: avoid_print
import 'package:casl/casl.dart';

void main() {
  print('casl · ${DateTime.now().toIso8601String()}\n');

  _bench('build an index of 1 000 rules', 200, () {
    createMongoAbility(_rules(1000));
  });

  final wide = createMongoAbility(_rules(1000));
  final subjectType = 'Type${_rules(1000).length ~/ 2}';

  _bench('can() against a subject type, 1 000 rules', 200000, () {
    wide.can('read', subjectType);
  });

  final article = subject('Type1', const {'authorId': 7, 'published': true});
  _bench('can() against an instance, conditions evaluated', 200000, () {
    wide.can('update', article);
  });

  _bench('can() for an administrator — manage:all', 200000, () {
    _admin.can('read', 'Article');
  });

  final fielded = createMongoAbility([
    RawRule.of(action: 'update', subject: 'Article'),
    RawRule.of(
      action: 'update',
      subject: 'Article',
      fields: const ['secret'],
      inverted: true,
    ),
  ]);
  _bench(
    'can() with a field, on a rule set that has per-field rules',
    200000,
    () {
      fielded.can('update', 'Article', 'title');
    },
  );

  _bench('rulesToAst over 1 000 rules', 2000, () {
    rulesToAst(wide, 'read', 'Type1');
  });

  final packed = packRules(_rules(1000));
  _bench('unpackRules of 1 000 rules', 500, () {
    unpackRules(packed);
  });
}

final Ability _admin = createMongoAbility([
  RawRule.of(action: 'manage', subject: 'all'),
]);

List<RawRule> _rules(int count) => [
  for (var i = 0; i < count; i++)
    RawRule.of(
      action: i.isEven ? 'read' : 'update',
      subject: 'Type${i % 50}',
      conditions: i % 3 == 0 ? {'authorId': 7} : null,
    ),
];

void _bench(String name, int iterations, void Function() body) {
  // A warm-up pass, because the first few thousand calls measure the JIT.
  for (var i = 0; i < iterations ~/ 10 + 1; i++) {
    body();
  }

  final watch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    body();
  }
  watch.stop();

  final perOp = watch.elapsedMicroseconds / iterations;
  final rendered = perOp < 1
      ? '${(perOp * 1000).toStringAsFixed(0)} ns'
      : '${perOp.toStringAsFixed(2)} µs';

  print(
    '${rendered.padLeft(10)}  ${name.padRight(58)} '
    '($iterations×)',
  );
}
