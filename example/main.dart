// A screen that draws what the user may actually do.
//
// The three shapes worth knowing: hide it, disable it and say why, or just
// ask. The second is usually the kindest.
import 'package:casl_flutter/casl_flutter.dart';
import 'package:flutter/material.dart';

void main() {
  final ability = createMongoAbility([
    RawRule.of(action: 'read', subject: 'Article'),
    RawRule.of(
      action: 'update',
      subject: 'Article',
      conditions: const {'authorId': 7},
    ),
    RawRule.of(
      action: 'delete',
      subject: 'Article',
      inverted: true,
      reason: 'Published articles are kept for the audit trail.',
    ),
  ]);

  runApp(
    // Everything below can ask, and rebuilds when the rules change.
    AbilityProvider(
      ability: ability,
      child: ExampleApp(ability: ability),
    ),
  );
}

/// The demo app.
class ExampleApp extends StatelessWidget {
  /// Creates it.
  const ExampleApp({required this.ability, super.key});

  /// Held only so the button below can change the rules at runtime.
  final Ability ability;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text('casl_flutter')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Hidden entirely when not permitted — right for something the user
          // has no reason to expect.
          const Can(
            'create',
            'Article',
            child: ListTile(title: Text('New article')),
          ),

          // Kept and disabled, with the rule's own explanation. Right whenever
          // its absence would prompt a question.
          CanBuilder(
            'delete',
            subject('Article', const {'authorId': 7}),
            builder: (context, can) => Tooltip(
              message: can.reason ?? '',
              child: ListTile(
                title: const Text('Delete article'),
                enabled: can.allowed,
                onTap: can.allowed ? () {} : null,
              ),
            ),
          ),

          // The plain question, for anything a widget cannot express.
          if (context.can('read', 'Article'))
            const ListTile(title: Text('Article list')),

          const Divider(),

          // Rules change in place; the list above follows without navigating.
          ElevatedButton(
            onPressed: () =>
                ability.update([RawRule.of(action: 'manage', subject: 'all')]),
            child: const Text('Promote me to administrator'),
          ),
        ],
      ),
    ),
  );
}
