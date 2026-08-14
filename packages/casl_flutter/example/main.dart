// A screen that draws what the user may actually do.
//
// Everything here is one of four shapes, and the fourth is the one people
// forget:
//
//   1. hide it            — `Can`, for a control they have no reason to expect
//   2. say something else — `Can(otherwise:)`, for an upsell or a badge
//   3. keep it and say why — `CanBuilder`, which is usually the kindest
//   4. ask what the *fields* are — `permittedFieldsOf`, for a form
//
// Run it with `flutter run -t example/main.dart` from `packages/casl_flutter`.
import 'package:casl_flutter/casl_flutter.dart';
import 'package:flutter/material.dart';

// ---------------------------------------------------------------- vocabulary
//
// Declared once, so a misspelled action stops compiling rather than silently
// denying forever. Extension types erase completely: these *are* strings at
// runtime, and the rules below travel over the wire unchanged.

/// Everything anybody may attempt in this app.
extension type const AppAction(String wire) implements String {
  /// Read an article.
  static const read = AppAction('read');

  /// Create one.
  static const create = AppAction('create');

  /// Change one.
  static const update = AppAction('update');

  /// Remove one.
  static const delete = AppAction('delete');

  /// Publish one, which only a moderator may do.
  static const publish = AppAction('publish');
}

/// Everything those actions can be attempted on.
extension type const AppSubject(String wire) implements String {
  /// An article.
  static const article = AppSubject('Article');
}

/// `Can`, with the action type pinned. `AppCan('reed', …)` does not compile.
typedef AppCan = Can<AppAction>;

/// `CanBuilder`, likewise.
typedef AppCanBuilder = CanBuilder<AppAction>;

/// The ability type this app passes around.
typedef AppAbility = Ability<AppAction, AppSubject>;

// --------------------------------------------------------------------- rules
//
// In a real app this arrives from the server as JSON and is read with
// `unpackRules`. It is written out here so the example runs on its own — and
// because *this function* is the thing worth unit-testing, not `can`.

/// Who the signed-in person is.
enum Role {
  /// Reads published articles and nothing else.
  viewer,

  /// Writes their own.
  author,

  /// Everything, plus publishing.
  moderator,
}

const _currentUserId = 7;

/// The rules for [role]. The whole of this app's authorisation policy.
List<RawRule> rulesFor(Role role) =>
    defineAbility<AppAction, AppSubject>((can, cannot) {
      // Everyone reads what is published.
      can(AppAction.read, AppSubject.article, {'published': true});

      if (role == Role.viewer) return;

      // Authors read and change their own, published or not.
      can(AppAction.create, AppSubject.article);
      can.each(
        const [AppAction.read, AppAction.update],
        AppSubject.article,
        {'authorId': _currentUserId},
      );

      // …but not the title once it is out in the world.
      cannot(
        AppAction.update,
        AppSubject.article,
        {'published': true},
        const ['title'],
      ).because('the title of a published article is fixed');

      if (role == Role.author) {
        cannot(AppAction.delete, AppSubject.article, {
          'published': true,
        }).because('published articles are kept for the audit trail');
        return;
      }

      can.each(const [AppAction.delete, AppAction.publish], AppSubject.article);
    }).rules;

// -------------------------------------------------------------------- models

class _Article with CaslSubject, CaslRecord {
  const _Article({
    required this.id,
    required this.title,
    required this.authorId,
    required this.published,
  });

  final int id;
  final String title;
  final int authorId;
  final bool published;

  // Declared rather than reflected: `runtimeType` is renamed by `--obfuscate`,
  // so relying on it would authorise differently in the build that ships.
  @override
  String get caslSubjectType => 'Article';

  // Lets a rule's conditions read this object directly, with no conversion to
  // a map on every check.
  @override
  Object? caslField(String name) => switch (name) {
    'id' => id,
    'title' => title,
    'authorId' => authorId,
    'published' => published,
    _ => null,
  };
}

const _articles = [
  _Article(id: 1, title: 'Mine, draft', authorId: 7, published: false),
  _Article(id: 2, title: 'Mine, published', authorId: 7, published: true),
  _Article(id: 3, title: 'Theirs, published', authorId: 9, published: true),
  _Article(id: 4, title: 'Theirs, draft', authorId: 9, published: false),
];

const _articleFields = ['title', 'body', 'published'];

// ----------------------------------------------------------------------- app

void main() => runApp(const ExampleApp());

/// The demo.
class ExampleApp extends StatefulWidget {
  /// Creates it.
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  final AppAbility _ability = createMongoAbility<AppAction, AppSubject>(
    rulesFor(Role.viewer),
  );
  Role _role = Role.viewer;

  void _signInAs(Role role) {
    setState(() => _role = role);
    // One call replaces the whole grant. Everything below redraws itself;
    // nothing has to navigate, and nothing has to be told.
    _ability.update(rulesFor(role));
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'casl_flutter',
    theme: ThemeData(useMaterial3: true),
    // Everything under here can ask, and rebuilds when the rules change.
    home: AbilityProvider(
      ability: _ability,
      child: _HomePage(role: _role, onSignInAs: _signInAs),
    ),
  );
}

class _HomePage extends StatelessWidget {
  const _HomePage({required this.role, required this.onSignInAs});

  final Role role;
  final ValueChanged<Role> onSignInAs;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Articles'),
      actions: const [
        // 1. Hidden entirely — right for something they have no reason to
        //    expect to be there.
        AppCan(
          AppAction.create,
          AppSubject.article,
          child: IconButton(onPressed: null, icon: Icon(Icons.add)),
        ),
      ],
    ),
    body: ListView(
      children: [
        _RolePicker(role: role, onChanged: onSignInAs),
        const Divider(height: 1),
        for (final article in _articles) _ArticleTile(article: article),
        const Divider(height: 1),
        const _FieldRestrictedForm(),
      ],
    ),
  );
}

class _RolePicker extends StatelessWidget {
  const _RolePicker({required this.role, required this.onChanged});

  final Role role;
  final ValueChanged<Role> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: SegmentedButton<Role>(
      segments: [
        for (final r in Role.values)
          ButtonSegment(value: r, label: Text(r.name)),
      ],
      selected: {role},
      onSelectionChanged: (selected) => onChanged(selected.first),
    ),
  );
}

class _ArticleTile extends StatelessWidget {
  const _ArticleTile({required this.article});

  final _Article article;

  @override
  Widget build(BuildContext context) {
    // Asked about the *instance*, so conditions are evaluated. Asking about
    // `AppSubject.article` instead would answer "is there any article I may
    // delete", which is the question a menu wants and not this one.
    if (context.cannot(AppAction.read, article)) return const SizedBox.shrink();

    return ListTile(
      title: Text(article.title),
      subtitle: Text(article.published ? 'published' : 'draft'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 3. Kept, disabled, and explained. `reason` is null unless a rule
          //    actually said something, so the tooltip appears only when there
          //    is something worth reading.
          AppCanBuilder(
            AppAction.delete,
            article,
            builder: (context, can) => Tooltip(
              message: can.reason ?? '',
              child: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: can.allowed ? () {} : null,
              ),
            ),
          ),

          // 2. Something else in its place.
          AppCan(
            AppAction.publish,
            article,
            otherwise: const Icon(Icons.lock_outline, size: 18),
            child: IconButton(
              icon: const Icon(Icons.publish_outlined),
              onPressed: () {},
            ),
          ),
        ],
      ),
    );
  }
}

/// 4. A form that draws the boxes the rules allow, rather than drawing them all
/// and refusing on submit.
class _FieldRestrictedForm extends StatelessWidget {
  const _FieldRestrictedForm();

  @override
  Widget build(BuildContext context) {
    const draft = _Article(
      id: 2,
      title: 'Mine, published',
      authorId: 7,
      published: true,
    );

    final editable = permittedFieldsOf(
      context.ability,
      AppAction.update,
      draft,
      allFields: _articleFields,
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Editing "${draft.title}"',
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 8),
          if (editable.isEmpty)
            const Text('Nothing here is yours to change.')
          else
            for (final field in editable)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: TextField(
                  decoration: InputDecoration(
                    labelText: field,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
