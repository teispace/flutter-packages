import 'package:casl/src/alias.dart';
import 'package:casl/src/fields/field_pattern.dart';
import 'package:casl/src/matchers.dart';
import 'package:casl/src/raw_rule.dart';
import 'package:casl/src/rule.dart';
import 'package:casl/src/subject.dart';
import 'package:meta/meta.dart';

/// Rules, indexed by subject type and action so a check does not scan them all.
///
/// Split out from `Ability` because it is a different job: this decides
/// which rules *could* apply, and the ability decides what that means.
/// Everything to do with ordering lives here.
///
/// ## Type parameters
///
/// [A] is the action type and [S] the subject type, both bounded by `String`
/// because that is what they are on the wire. Leave them off and they infer as
/// `String`, which is the untyped behaviour; supply extension types over
/// `String` and a misspelled action stops compiling. See `Ability`.
///
/// Not usually constructed directly — see `Ability`.
class RuleIndex<A extends String, S extends String> {
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
  ///
  /// Capped, because both halves of the key can come from data: a subject type
  /// read out of a payload, an action out of a deep link. An unbounded map
  /// keyed by anything a caller passes is a slow leak, and a permission check
  /// is exactly the kind of call that happens on every frame.
  ///
  /// Past the cap the answer is still correct — it is simply recomputed, which
  /// is a merge of two sorted lists. CASL.js caches only pairs its index
  /// already knows, which leaks nothing but also never caches the
  /// `manage`/`all` fan-in that an administrator's whole grant depends on.
  final Map<String, Map<String, List<Rule>>> _merged = {};
  int _mergedEntries = 0;

  /// How many `(subject type, action)` pairs are worth remembering.
  ///
  /// A real application has tens of subject types and tens of actions. This is
  /// far above that and far below a leak.
  static const int _mergedCacheLimit = 512;

  bool _hasPerFieldRules = false;

  /// The raw rules, in the order they were given.
  List<RawRule> get rules => List.unmodifiable(_rules);

  /// How many `(subject type, action)` lookups are currently remembered.
  ///
  /// Exposed so the cap that stops [_merged] growing without bound can be
  /// tested rather than asserted. Nothing else should read it.
  @visibleForTesting
  int get cachedLookupCount => _mergedEntries;

  /// Replaces every rule.
  ///
  /// The whole set at once, never one at a time: a rule's meaning depends on
  /// what surrounds it, so there is no sound way to add one in isolation.
  ///
  /// Returns itself, as CASL.js's `update` does, so a call site ported from
  /// JavaScript keeps compiling.
  RuleIndex<A, S> update(List<RawRule> rules) {
    _rules = rules;
    _indexed.clear();
    _merged.clear();
    _mergedEntries = 0;
    _hasPerFieldRules = false;
    _index(rules);
    // Chainable for parity with CASL.js, where `update` returns the ability.
    // The lint prefers a cascade, which is the right default and the wrong
    // answer for a signature that exists to match another language's.
    // ignore: avoid_returning_this
    return this;
  }

  /// Compiles every rule's conditions now, so a rule this client cannot read
  /// is found here rather than on the screen that first checks it.
  ///
  /// Conditions are otherwise compiled **lazily**, and more lazily than it
  /// looks: a rule checked only against a subject *type* never compiles them at
  /// all, because there is nothing to evaluate them against. So a rule carrying
  /// an operator this client does not know can sit unnoticed through
  /// `can('read', 'Article')` and only throw when somebody opens a list and the
  /// first *instance* is checked.
  ///
  /// That is the wrong place to find out. Call this straight after taking rules
  /// from a server, where the failure is still yours to handle:
  ///
  /// ```dart
  /// ability.update(unpackRules(payload));
  /// try {
  ///   ability.validateRules();
  /// } on ConditionFormatException catch (error) {
  ///   log.warning('the server sent a rule this build cannot read', error);
  /// }
  /// ```
  ///
  /// `UnparsableCondition.deny` is the other half of the answer: with it, such
  /// a rule grants nothing instead of throwing at all.
  void validateRules() {
    // Rules are indexed once per subject × action, so most are met several
    // times. Compilation is cached on the rule, so the repeats cost a null
    // check each.
    for (final byAction in _indexed.values) {
      for (final rules in byAction.values) {
        for (final rule in rules) {
          rule.compileConditions();
        }
      }
    }
  }

  /// Which subject type [value] should be checked as.
  ///
  /// A bare string is already one. Null — as in `can('read')` on an ability
  /// with no subjects — is [anySubjectTypeName].
  ///
  /// The result is typed as [S], which is a cast rather than a proof: subject
  /// types are strings at runtime, so nothing checks that a detected name is
  /// one your vocabulary declares. That is inherent to erasing the type, and it
  /// is the same guarantee TypeScript gives.
  S detectSubjectType(Object? value) {
    if (value == null) return anySubjectTypeName as S;
    if (value is String) return value as S;
    return _detectSubjectType(value) as S;
  }

  /// Every rule that could apply to [action] on [subjectType], best first.
  ///
  /// "Could" because conditions have not been evaluated — that needs an
  /// instance, and this takes a type. The result folds in rules written about
  /// [anyActionName] and [anySubjectTypeName], which is all those two are:
  /// ordinary index entries that everything merges with.
  List<Rule> possibleRulesFor(A action, [S? subjectType]) {
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

    if (_mergedEntries < _mergedCacheLimit) {
      (_merged[type] ??= {})[action] = result;
      _mergedEntries++;
    }

    return result;
  }

  /// Every rule that could apply, narrowed to one [field].
  ///
  /// A null [field] means "any field at all", which is a different question —
  /// see [Rule.matchesField].
  List<Rule> rulesFor(A action, [S? subjectType, String? field]) {
    final rules = possibleRulesFor(action, subjectType);
    if (!_hasPerFieldRules) return rules;

    // Allocated only once something is actually filtered out, which on a rule
    // set with any per-field rules at all is the minority of calls — and this
    // runs once per row of a list. The copy starts as everything kept so far,
    // so the common path returns the original list untouched.
    List<Rule>? kept;
    for (var i = 0; i < rules.length; i++) {
      if (rules[i].matchesField(field)) {
        kept?.add(rules[i]);
      } else {
        kept ??= rules.sublist(0, i);
      }
    }

    return kept ?? rules;
  }

  /// Every action any rule mentions for [subjectType].
  ///
  /// For building a UI that lists what a role can do, rather than asking about
  /// one action at a time.
  Set<A> actionsFor(S subjectType) => {
    ...?_indexed[subjectType]?.keys.cast<A>(),
    if (subjectType != anySubjectTypeName)
      ...?_indexed[anySubjectTypeName]?.keys.cast<A>(),
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
  ///
  /// ## Equal priorities are the same rule
  ///
  /// A priority is assigned once per rule, from its position in the rule list,
  /// so two entries sharing one are not two rules that happen to tie — they are
  /// one rule reached by two paths. That happens whenever a rule names both a
  /// specific action and [anyActionName], or both a subject type and
  /// [anySubjectTypeName]:
  ///
  /// ```dart
  /// RawRule.of(action: ['read', 'manage'], subject: 'Article');
  /// ```
  ///
  /// is indexed under `read` *and* under `manage`, and merging those two
  /// buckets meets it twice. Taking it once is the whole of the deduplication;
  /// without it `can` still answers correctly, but `rulesToCondition` emits a
  /// duplicated branch and every check pays for the extra entry.
  static List<Rule> _mergeByPriority(List<Rule>? a, List<Rule>? b) {
    if (a == null || a.isEmpty) return b ?? const [];
    if (b == null || b.isEmpty) return a;

    final merged = <Rule>[];
    var i = 0;
    var j = 0;
    while (i < a.length && j < b.length) {
      if (a[i].priority < b[j].priority) {
        merged.add(a[i++]);
      } else if (a[i].priority > b[j].priority) {
        merged.add(b[j++]);
      } else {
        merged.add(a[i++]);
        j++;
      }
    }
    merged
      ..addAll(a.skip(i))
      ..addAll(b.skip(j));

    return merged;
  }
}
