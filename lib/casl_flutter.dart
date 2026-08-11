/// Flutter bindings for [casl](https://pub.dev/packages/casl).
///
/// Put an ability in the tree, then ask what the user may do wherever you are
/// drawing something:
///
/// ```dart
/// AbilityProvider(
///   ability: ability,
///   child: MaterialApp(...),
/// );
///
/// // anywhere below it
/// Can('delete', article, child: DeleteButton(article: article));
/// CanBuilder('delete', article, builder: (_, allowed) => ...);
/// if (context.can('create', 'Article')) ...;
/// ```
///
/// Every question here is answered by `casl` itself, so a rule means the same
/// thing on the server, in a unit test and on screen. This package adds only
/// the wiring: where the ability lives, and how a widget hears that it changed.
///
/// `package:casl` is re-exported, so one import is enough.
library;

export 'package:casl/casl.dart';

export 'src/ability_provider.dart';
export 'src/can.dart';
export 'src/context_extensions.dart';
