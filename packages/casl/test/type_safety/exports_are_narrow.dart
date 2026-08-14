// Deliberately does not compile. `test/hygiene_test.dart` explains why it
// exists; `test/exports_test.dart` analyses it and asserts each error.
//
// Every name below used to be exported from `package:casl/casl.dart` and is
// not any more. They are ordinary words an application is quite likely to want
// for itself — and a package that forces `hide` clauses on a common import is
// a package people put down.
//
// Excluded from the package's own analysis, so `melos run analyze` stays green.
import 'package:casl/casl.dart';

void main() {
  // Replaced by `CaslFields.read` / `.path` / `.parent` / `.has`.
  readField(const {'a': 1}, 'a');
  readPath(const {'a': 1}, 'a');
  readParent(const {'a': 1}, 'a');
  hasField(const {'a': 1}, 'a');

  // Replaced by `Condition.always` / `Condition.never`.
  print(alwaysTrue);
  print(alwaysFalse);

  // Internal chores that leaked. `RawRule.of` is how you reach the first, and
  // nothing outside the package needs the other two.
  oneOrMany('read', 'action');
  subjectValue(subject('Article', const {}));
  isSubjectType('Article');

  // Renamed to `ForcedSubject`, because `Subject` collides with rxdart's and
  // an unused collision is fine right up until somebody uses it.
  print(Subject);
}
