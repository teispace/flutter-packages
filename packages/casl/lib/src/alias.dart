import 'package:casl/src/subject.dart';

/// Expands an action into itself plus everything it stands for.
typedef ResolveActions = List<String> Function(List<String> actions);

/// Builds a resolver from a map of alias to what it means.
///
/// ```dart
/// final resolve = createAliasResolver({
///   'modify': ['update', 'delete'],
///   'access': ['read', 'modify'],
/// });
/// ```
///
/// An alias may point at another alias, and the chain is followed. `access`
/// above resolves to `read`, `update`, `delete` — so `can('access', 'Article')`
/// grants a `delete` check.
///
/// ## Why this validates so aggressively
///
/// Both mistakes it catches produce an ability that is *wrong* rather than one
/// that fails. A cycle would loop forever or silently truncate; aliasing the
/// wildcard action would make one alias quietly grant everything. Neither is
/// visible in a passing test that happens not to use the alias.
///
/// [anyActionName] is the action that already means "everything" — `manage` by
/// default, and it must match the ability's.
ResolveActions createAliasResolver(
  Map<String, Object> aliases, {
  String anyActionName = anyAction,
  bool validate = true,
}) {
  final expanded = <String, List<String>>{
    for (final entry in aliases.entries)
      entry.key: switch (entry.value) {
        final String single => [single],
        final Iterable<Object?> many => many.cast<String>().toList(),
        _ => throw ArgumentError.value(
          entry.value,
          entry.key,
          'an alias must map to a String or a List<String>',
        ),
      },
  };

  if (validate) {
    if (expanded.containsKey(anyActionName)) {
      throw ArgumentError.value(
        anyActionName,
        'aliases',
        'cannot alias "$anyActionName" because it already means every action',
      );
    }
    for (final name in expanded.keys) {
      _walk(expanded, [name], anyActionName, {name});
    }
  }

  return (actions) {
    final result = <String>[];
    final seen = <String>{};
    void add(String action) {
      if (!seen.add(action)) return;
      result.add(action);
      (expanded[action] ?? const <String>[]).forEach(add);
    }

    actions.forEach(add);
    return result;
  };
}

void _walk(
  Map<String, List<String>> aliases,
  List<String> path,
  String anyActionName,
  Set<String> visiting,
) {
  for (final target in aliases[path.last] ?? const <String>[]) {
    if (target == anyActionName) {
      throw ArgumentError.value(
        path.first,
        'aliases',
        'cannot alias "$anyActionName" because it already means every action',
      );
    }
    if (visiting.contains(target)) {
      throw ArgumentError.value(
        path.first,
        'aliases',
        'cycle detected: ${[...path, target].join(' -> ')}',
      );
    }
    if (aliases.containsKey(target)) {
      _walk(aliases, [...path, target], anyActionName, {...visiting, target});
    }
  }
}
