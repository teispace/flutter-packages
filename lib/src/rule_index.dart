import 'package:casl/src/alias.dart';
import 'package:casl/src/fields/field_pattern.dart';
import 'package:casl/src/matchers.dart';
import 'package:casl/src/raw_rule.dart';
import 'package:casl/src/rule.dart';
import 'package:casl/src/subject.dart';

/// Rules, indexed by subject type and action so a check does not scan them all.
///
/// Split out from `PureAbility` because it is a different job: this decides
/// which rules *could* apply, and the ability decides what that means.
/// Everything to do with ordering lives here.
///
/// Not usually constructed directly — see `PureAbility`.
class RuleIndex {
  /// Indexes [rules].
  RuleIndex(
    List<RawRule> rules, {
    // Private fields as initializing formals — callers still write
    // `conditionsMatcher:`, because Dart exposes a private field under its
    // public name.
    this._conditionsMatcher,
    // Defaulted, unlike the conditions matcher. CASL.js requires this one too,
    // and the deviation is deliberate: a condition language is a real choice,
    // whereas `*` and `**` mean one thing everywhere. Defaulting it cannot
    // change what any rule means — it only replaces a throw with the answer
    // everyone was going to supply anyway.
    this._fieldsMatcher = defaultFieldsMatcher,
    this._resolveActions,
    DetectSubjectType? detectSubjectType,
    this.anyActionName = anyAction,
    this.anySubjectTypeName = anySubjectType,
  }) : _detectSubjectType = detectSubjectType ?? detectSubjectTypeByRuntimeType,
       _rules = rules {
    _index(rules);
  }

  /// The action that means "any action". `manage` by default.
  final String anyActionName;

  /// The subject type that means "any subject type". `all` by default.
  final String anySubjectTypeName;

  final ConditionsMatcher? _conditionsMatcher;
  final FieldsMatcher _fieldsMatcher;
  final ResolveActions? _resolveActions;
  final DetectSubjectType _detectSubjectType;

  List<RawRule> _rules;

  /// subject type -> action -> the rules for it, ordered by priority.
  final Map<String, Map<String, List<Rule>>> _indexed = {};

  /// Merged results, so the fan-in from `manage` and `all` is paid once.
  final Map<String, Map<String, List<Rule>>> _merged = {};

  bool _hasPerFieldRules = false;

  /// The raw rules, in the order they were given.
  List<RawRule> get rules => List.unmodifiable(_rules);

  /// Replaces every rule.
  ///
  /// The whole set at once, never one at a time: a rule's meaning depends on
  /// what surrounds it, so there is no sound way to add one in isolation.
  void update(List<RawRule> rules) {
    _rules = rules;
    _indexed.clear();
    _merged.clear();
    _hasPerFieldRules = false;
    _index(rules);
  }

  /// Which subject type [value] should be checked as.
  ///
  /// A bare string is already one. Null — as in `can('read')` on an ability
  /// with no subjects — is [anySubjectTypeName].
  String detectSubjectType(Object? value) {
    if (value == null) return anySubjectTypeName;
    if (value is String) return value;
    return _detectSubjectType(value);
  }

  /// Every rule that could apply to [action] on [subjectType], best first.
  ///
  /// "Could" because conditions have not been evaluated — that needs an
  /// instance, and this takes a type. The result folds in rules written about
  /// [anyActionName] and [anySubjectTypeName], which is all those two are:
  /// ordinary index entries that everything merges with.
  List<Rule> possibleRulesFor(String action, [String? subjectType]) {
    final type = subjectType ?? anySubjectTypeName;

    final cached = _merged[type]?[action];
    if (cached != null) return cached;

    final forType = _indexed[type];
    var result = _mergeByPriority(
      forType?[action],
      action == anyActionName ? null : forType?[anyActionName],
    );

    if (type != anySubjectTypeName) {
      result = _mergeByPriority(result, possibleRulesFor(action));
    }

    (_merged[type] ??= {})[action] = result;
    return result;
  }

  /// Every rule that could apply, narrowed to one [field].
  ///
  /// A null [field] means "any field at all", which is a different question —
  /// see [Rule.matchesField].
  List<Rule> rulesFor(String action, [String? subjectType, String? field]) {
    final rules = possibleRulesFor(action, subjectType);
    if (!_hasPerFieldRules) return rules;

    return [
      for (final rule in rules)
        if (rule.matchesField(field)) rule,
    ];
  }

  /// Every action any rule mentions for [subjectType].
  ///
  /// For building a UI that lists what a role can do, rather than asking about
  /// one action at a time.
  Set<String> actionsFor(String subjectType) => {
    ...?_indexed[subjectType]?.keys,
    if (subjectType != anySubjectTypeName)
      ...?_indexed[anySubjectTypeName]?.keys,
  };

  /// Indexes [rules] **backwards**, so the last one declared gets priority 0.
  ///
  /// This is the whole of CASL's precedence, and it is worth being explicit
  /// about because it is the thing people assume wrongly: a later rule beats an
  /// earlier one, whether it permits or forbids. `cannot` does not trump `can`
  /// — it is simply usually written afterwards.
  void _index(List<RawRule> rules) {
    for (var i = rules.length - 1; i >= 0; i--) {
      final rule = Rule(
        rules[i],
        priority: rules.length - i - 1,
        conditionsMatcher: _conditionsMatcher,
        fieldsMatcher: _fieldsMatcher,
        resolveActions: _resolveActions,
      );

      if (rules[i].fields != null) _hasPerFieldRules = true;

      for (final subjectType in rules[i].subjects) {
        final forType = _indexed[subjectType] ??= {};
        for (final action in rule.actions) {
          (forType[action] ??= []).add(rule);
        }
      }
    }
  }

  /// Interleaves two priority-ordered lists, keeping them ordered.
  ///
  /// Both inputs are already sorted, so this is the merge step of a merge sort
  /// rather than a sort — which is what makes folding in the wildcard buckets
  /// cheap enough to do on every check.
  static List<Rule> _mergeByPriority(List<Rule>? a, List<Rule>? b) {
    if (a == null || a.isEmpty) return b ?? const [];
    if (b == null || b.isEmpty) return a;

    final merged = <Rule>[];
    var i = 0;
    var j = 0;
    while (i < a.length && j < b.length) {
      if (a[i].priority <= b[j].priority) {
        merged.add(a[i++]);
      } else {
        merged.add(b[j++]);
      }
    }
    merged
      ..addAll(a.skip(i))
      ..addAll(b.skip(j));

    return merged;
  }
}
