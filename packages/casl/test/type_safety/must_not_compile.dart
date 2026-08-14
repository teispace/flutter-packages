// Deliberately does not compile. See `test/typed_test.dart`, which analyses
// this file and asserts each error below is reported.
//
// Excluded from the package's own analysis, so `melos run analyze` stays green.
import 'package:casl/casl.dart';

extension type const AppAction(String wire) implements String {
  static const read = AppAction('read');
}
extension type const OtherAction(String wire) implements String {
  static const read = OtherAction('read');
}
extension type const AppSubject(String wire) implements String {
  static const article = AppSubject('Article');
}

void main() {
  final ability = createMongoAbility<AppAction, AppSubject>(const []);

  ability.can('read', 'Article');
  ability.can(OtherAction.read);
  ability.actionsFor('Article');

  final builder = AbilityBuilder<AppAction, AppSubject>()
    ..can(AppAction.read, 'Article');
}
