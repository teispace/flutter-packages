// Compiles every fenced Dart block in every README.
//
//   dart run tool/doc_snippets/check.dart
//
// Documentation that does not compile is worse than no documentation: it is
// confidently wrong, and a reader trusts it. Two of the defects in this
// repository's first audit were exactly that — a snippet passing a named
// argument that is positional, and one calling `build()` on rules that made it
// throw. Both were found by a person reading. This is so the next one is not.
//
// Two escapes, both deliberate and both visible:
//
//   * A block whose text contains `✗` is expected **not** to compile — that is
//     how the documentation marks "this is the mistake" — and the check is
//     inverted for it. So a counter-example that quietly starts compiling fails
//     too: it has stopped being a counter-example and the prose has gone stale.
//
//   * A block preceded by `<!-- continues -->` is compiled with the previous
//     blocks' top-level declarations in scope, which is how documentation
//     actually reads: declare a vocabulary, then use it in the next block.
//
//   * A block preceded by `<!-- fragment: why -->` is skipped. Some blocks are
//     illustrations rather than code — a table of condition syntax, a cascade
//     shown without its subject — and forcing those to compile would ruin what
//     they are for. The reason is required, and the count is printed, so this
//     cannot quietly become the way every awkward block gets waved through.
// ignore_for_file: avoid_print
import 'dart:io';

Future<void> main() async {
  final failures = <String>[];

  for (final package in _packages) {
    stdout.write('${package.name.padRight(16)} ');

    final all = _blocksIn(File(package.readme));
    final fragments = all.where((block) => block.fragmentReason != null);
    final blocks = all.where((block) => block.fragmentReason == null).toList();
    final dir = Directory('${package.root}/.doc_snippets')
      ..createSync(recursive: true);
    for (final entry in dir.listSync()) {
      entry.deleteSync();
    }
    // Declarations carry forward across a `<!-- continues -->` chain, and the
    // chain breaks at the first block that does not ask to continue.
    final carried = StringBuffer();
    for (final block in all) {
      if (!block.continues) carried.clear();
      if (block.fragmentReason == null) {
        File('${dir.path}/${block.fileName}').writeAsStringSync(
          package.wrap(block, carried.toString()),
        );
      }
      carried.writeln(block.parts.$2);
    }

    // A hidden directory, and every file by name.
    //
    // `dart format` and `dart analyze .` both skip a directory starting with a
    // dot, so generated snippets stay out of `melos run format` and
    // `melos run analyze` without any exclude to maintain — and the analyzer
    // still reads an explicitly named file inside one, which is what makes
    // checking them possible at all.
    final result = await Process.run(
      package.analyzer,
      [
        'analyze',
        '--no-fatal-warnings',
        for (final block in blocks) '.doc_snippets/${block.fileName}',
      ],
      workingDirectory: package.root,
    );

    // Errors only. A lint firing inside a snippet says something about the
    // snippet's style, not about whether a reader can run it.
    final errors = '${result.stdout}${result.stderr}'
        .split('\n')
        .where((line) => line.contains(' error '))
        .join('\n');

    final broken = [
      for (final block in blocks)
        if (errors.contains(block.fileName) != block.mustNotCompile) block,
    ];

    final skipped =
        fragments.isEmpty ? '' : ' (+${fragments.length} illustrative)';

    if (broken.isEmpty) {
      print('${blocks.length} blocks ✓$skipped');
      continue;
    }

    print('${blocks.length} blocks$skipped — ${broken.length} wrong');
    for (final block in broken) {
      final why = block.mustNotCompile
          ? 'compiles, but the prose marks it ✗'
          : 'does not compile';
      failures.add('${package.readme}:${block.line} — $why');
    }
    // Only the errors from blocks that are actually wrong. A counter-example
    // reporting exactly the error it advertises is not news.
    print(
      errors
          .split('\n')
          .where((line) => broken.any((b) => line.contains(b.fileName)))
          .join('\n')
          .trim(),
    );
  }

  if (failures.isEmpty) {
    print('\nEvery documented snippet compiles.');
    return;
  }

  print('\n${failures.length} problem(s):');
  for (final failure in failures) {
    print('  $failure');
  }
  exitCode = 1;
}

/// One fenced block, and where it came from.
final class _Block {
  const _Block(
    this.line,
    this.source, {
    required this.fragmentReason,
    required this.continues,
  });

  /// The line the fence opens on, so a failure points back at the README.
  final int line;

  /// What is between the fences.
  final String source;

  /// Why this block is an illustration rather than code, when it is one.
  final String? fragmentReason;

  /// Whether the blocks before it are in scope.
  final bool continues;

  /// The generated file, named after the line so a failure is traceable.
  String get fileName => 'block_$line.dart';

  /// Marked in the prose as a mistake, so it is expected not to compile.
  bool get mustNotCompile => source.contains('✗');

  /// Splits the block into imports, top-level declarations and statements.
  ///
  /// Documentation mixes all three freely — an import, a class, then a line
  /// using it — and Dart has neither local classes nor directives after
  /// declarations, so a block cannot simply be wrapped whole.
  (String imports, String declarations, String statements) get parts {
    final imports = <String>[];
    final declarations = <String>[];
    final statements = <String>[];
    var depth = 0;
    var inDeclaration = false;

    for (final line in source.split('\n')) {
      if (depth == 0 && !inDeclaration && line.startsWith('import ')) {
        imports.add(line);
        continue;
      }

      if (depth == 0 && !inDeclaration && _startsDeclaration(line)) {
        inDeclaration = true;
      }

      (inDeclaration ? declarations : statements).add(line);

      depth += '{'.allMatches(line).length - '}'.allMatches(line).length;
      if (inDeclaration &&
          depth == 0 &&
          (line.trim().endsWith(';') || line.trimRight().endsWith('}'))) {
        inDeclaration = false;
      }
    }

    return (
      imports.join('\n'),
      declarations.join('\n'),
      statements.join('\n'),
    );
  }

  static bool _startsDeclaration(String line) =>
      _declarationKeyword.hasMatch(line) || _topLevelFunction.hasMatch(line);

  static final _declarationKeyword = RegExp(
    '^(export|part|@|abstract |base |final class|sealed |'
    'class |mixin |enum |typedef |extension |void main)',
  );

  /// `Condition parseMod(OperatorCall call) {` and friends.
  ///
  /// A local function would compile perfectly well inside the wrapper, so this
  /// is not about validity — it is about `<!-- continues -->`, which can only
  /// carry forward what sits at the top level.
  ///
  /// A return type, whitespace, a name, then an open bracket. `ability.can(…)`
  /// has no space before its bracket and so does not match, and an indented
  /// line cannot match at all because the pattern is anchored.
  static final _topLevelFunction = RegExp(
    r'^[A-Za-z_][A-Za-z0-9_<>?, ]*\s[a-z_][A-Za-z0-9_]*\s*\(',
  );
}

final class _Package {
  const _Package({
    required this.name,
    required this.root,
    required this.readme,
    required this.analyzer,
    required this.imports,
    required this.declarations,
  });

  final String name;
  final String root;
  final String readme;

  /// `dart` or `flutter` — a Flutter package needs the Flutter analyzer.
  final String analyzer;

  /// What every generated file imports.
  final String imports;

  /// Names a snippet may assume exist, because the prose establishes them and
  /// repeating them in every block would drown the point being made.
  final String declarations;

  String wrap(_Block block, String carried) {
    final (snippetImports, snippetDeclarations, statements) = block.parts;

    return '''
// GENERATED from $readme, line ${block.line}. Do not edit.
// ignore_for_file: unused_local_variable, unused_element, unused_import
// ignore_for_file: avoid_print, avoid_redundant_argument_values, unused_field
// ignore_for_file: depend_on_referenced_packages, prefer_const_constructors
// ignore_for_file: prefer_const_literals_to_create_immutables, unnecessary_cast
// ignore_for_file: lines_longer_than_80_chars, public_member_api_docs
// ignore_for_file: cascade_invocations, omit_local_variable_types
// ignore_for_file: unnecessary_lambdas, avoid_positional_boolean_parameters
$imports
$snippetImports

$carried
$snippetDeclarations
$declarations

Future<void> _block() async {
$statements
}
''';
  }
}

const _caslDeclarations = '''
final ability = createMongoAbility(const []);
final admin = ability;
final builder = AbilityBuilder();
final article = subject('Article', const {'authorId': 7});
const currentUserId = 7;
const userId = 7;
const user = (id: 7, isModerator: true);
const json = <String, Object?>{'action': 'read'};
const payload = <List<Object?>>[];
final database = _Database();
final log = _Log();

class _Database {
  List<Object?> select(Object? where) => const [];
}

class _Log {
  void warning(Object? message, [Object? error]) {}
}
''';

const _packages = <_Package>[
  _Package(
    name: 'casl',
    root: 'packages/casl',
    readme: 'packages/casl/README.md',
    analyzer: 'dart',
    imports: "import 'package:casl/casl.dart';",
    declarations: _caslDeclarations,
  ),
  _Package(
    name: 'casl_flutter',
    root: 'packages/casl_flutter',
    readme: 'packages/casl_flutter/README.md',
    analyzer: 'flutter',
    imports: "import 'package:casl_flutter/casl_flutter.dart';\n"
        "import 'package:flutter/material.dart';",
    declarations: '$_caslDeclarations\n'
        'late BuildContext context;\n'
        'final notifier = AbilityNotifier(ability);\n',
  ),
];

List<_Block> _blocksIn(File readme) {
  final lines = readme.readAsLinesSync();
  final blocks = <_Block>[];

  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trimRight() != '```dart') continue;

    // `<!-- fragment: why -->` on the line before, or the line before that if
    // a blank line separates them.
    String? reason;
    var continues = false;
    for (final back in const [1, 2]) {
      if (i - back < 0) break;
      if (lines[i - back].trim() == '<!-- continues -->') continues = true;
    }
    for (final back in const [1, 2]) {
      if (i - back < 0) break;
      final match = RegExp(
        r'^<!--\s*fragment:\s*(.+?)\s*-->$',
      ).firstMatch(lines[i - back].trim());
      if (match != null) {
        reason = match.group(1);
        break;
      }
    }

    final body = <String>[];
    var j = i + 1;
    while (j < lines.length && lines[j].trimRight() != '```') {
      body.add(lines[j]);
      j++;
    }

    blocks.add(
      _Block(
        i + 1,
        body.join('\n'),
        fragmentReason: reason,
        continues: continues,
      ),
    );
    i = j;
  }

  return blocks;
}
