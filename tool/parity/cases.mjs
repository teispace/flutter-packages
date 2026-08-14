// The parity case table.
//
// Every entry is run through @casl/ability and its answer recorded; the Dart
// suite replays the recording. See README.md for the format and for how to
// record a deliberate deviation.
//
// Ids are stable identifiers, not descriptions — a failure names one, and a
// deviation is keyed by one, so renaming loses its history.

/** A regular expression, in the form both sides understand. */
export const re = (source, flags = '') => ({ '!re': source, flags });

/** A date, in the form both sides understand. */
export const date = (iso) => ({ '!date': new Date(iso).toISOString() });

/** An instance to check against, as opposed to a bare subject type. */
export const of_ = (type, value) => ({ type, value });

export const cases = [
  // ---------------------------------------------------------------- precedence
  {
    id: 'precedence/last-rule-wins',
    op: 'can',
    rules: [
      { action: 'read', subject: 'Article', inverted: true },
      { action: 'read', subject: 'Article' },
    ],
    check: { action: 'read', subject: 'Article' },
  },
  {
    id: 'precedence/cannot-after-can',
    op: 'can',
    rules: [
      { action: 'read', subject: 'Article' },
      { action: 'read', subject: 'Article', inverted: true },
    ],
    check: { action: 'read', subject: 'Article' },
  },
  {
    id: 'precedence/manage-all',
    op: 'can',
    rules: [{ action: 'manage', subject: 'all' }],
    check: { action: 'anything', subject: 'Whatever' },
  },
  {
    id: 'precedence/no-rules-denies',
    op: 'can',
    rules: [],
    check: { action: 'read', subject: 'Article' },
  },
  {
    id: 'precedence/claim-style-no-subject',
    op: 'can',
    rules: [{ action: 'publish' }],
    check: { action: 'publish' },
  },

  // ------------------------------------------------------- rule index (D-03)
  {
    id: 'index/duplicate-action-wildcard',
    op: 'rules',
    rules: [{ action: ['read', 'manage'], subject: 'Article' }],
    action: 'read',
    subjectType: 'Article',
  },
  {
    id: 'index/duplicate-subject-wildcard',
    op: 'rules',
    rules: [{ action: 'read', subject: ['Article', 'all'] }],
    action: 'read',
    subjectType: 'Article',
  },
  {
    id: 'index/actions-for',
    op: 'actions',
    rules: [
      { action: ['read', 'update'], subject: 'A' },
      { action: 'x', subject: 'all' },
    ],
    subjectType: 'A',
  },

  // ------------------------------------------------------------- conditions
  {
    id: 'conditions/eq-scalar-match',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { authorId: 7 } }],
    check: { action: 'read', subject: of_('A', { authorId: 7 }) },
  },
  {
    id: 'conditions/eq-scalar-miss',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { authorId: 7 } }],
    check: { action: 'read', subject: of_('A', { authorId: 8 }) },
  },
  {
    id: 'conditions/eq-int-vs-double',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { n: 7 } }],
    check: { action: 'read', subject: of_('A', { n: 7.0 }) },
  },
  {
    // D-01
    id: 'conditions/eq-object-value',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { meta: { x: 1 } } }],
    check: { action: 'read', subject: of_('A', { meta: { x: 1 } }) },
    deviates: {
      dart: true,
      reason:
        'The condition engine CASL.js delegates to compares with `===`, so it '
        + 'structurally cannot match a nested object or a whole array by value. '
        + 'We compare by value, which is what MongoDB itself does. Pass '
        + '`strictJsEquality: true` for bug-compatibility. See docs/PARITY.md D-01.',
    },
  },
  {
    // D-01
    id: 'conditions/eq-array-value',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { tags: ['a', 'b'] } }],
    check: { action: 'read', subject: of_('A', { tags: ['a', 'b'] }) },
    deviates: {
      dart: true,
      reason:
        'The condition engine CASL.js delegates to compares with `===`, so it '
        + 'structurally cannot match a nested object or a whole array by value. '
        + 'We compare by value, which is what MongoDB itself does. Pass '
        + '`strictJsEquality: true` for bug-compatibility. See docs/PARITY.md D-01.',
    },
  },
  {
    id: 'conditions/eq-scalar-against-array-field',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { tags: 'draft' } }],
    check: { action: 'read', subject: of_('A', { tags: ['draft', 'new'] }) },
  },
  {
    // D-02
    id: 'conditions/null-missing-nested-parent',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { 'a.b': null } }],
    check: { action: 'read', subject: of_('A', {}) },
  },
  {
    id: 'conditions/null-present-parent-missing-key',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { 'a.b': null } }],
    check: { action: 'read', subject: of_('A', { a: {} }) },
  },
  {
    id: 'conditions/null-top-level-missing-key',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { b: null } }],
    check: { action: 'read', subject: of_('A', {}) },
  },
  {
    id: 'conditions/null-explicit-null-value',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { b: null } }],
    check: { action: 'read', subject: of_('A', { b: null }) },
  },
  {
    id: 'conditions/nested-path',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { 'country.isoCode': 'UA' } }],
    check: { action: 'read', subject: of_('A', { country: { isoCode: 'UA' } }) },
  },
  {
    id: 'conditions/path-through-list-flattens',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { 'comments.author': 'a' } }],
    check: {
      action: 'read',
      subject: of_('A', { comments: [{ author: 'a' }, { author: 'b' }] }),
    },
  },
  {
    id: 'conditions/path-numeric-index',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { 'c.0.author': 'a' } }],
    check: { action: 'read', subject: of_('A', { c: [{ author: 'a' }, { author: 'b' }] }) },
  },
  {
    // D-11
    id: 'conditions/null-in-list-preserved',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { 'items.v': { $in: [null] } } }],
    check: { action: 'read', subject: of_('A', { items: [{ v: null }, { v: 1 }] }) },
  },
  {
    id: 'conditions/empty-conditions-match-everything',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: {} }],
    check: { action: 'read', subject: of_('A', { anything: 1 }) },
  },

  // -------------------------------------------------------------- operators
  {
    id: 'op/ne',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { s: { $ne: 'draft' } } }],
    check: { action: 'read', subject: of_('A', { s: 'published' }) },
  },
  {
    id: 'op/gt',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { n: { $gt: 3 } } }],
    check: { action: 'read', subject: of_('A', { n: 4 }) },
  },
  {
    id: 'op/gte-boundary',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { n: { $gte: 3 } } }],
    check: { action: 'read', subject: of_('A', { n: 3 }) },
  },
  {
    id: 'op/lt-lte-combined',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { n: { $gte: 10, $lte: 50 } } }],
    check: { action: 'read', subject: of_('A', { n: 50 }) },
  },
  {
    id: 'op/gt-string',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { s: { $gt: 'm' } } }],
    check: { action: 'read', subject: of_('A', { s: 'z' }) },
  },
  {
    id: 'op/gt-date',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { at: { $lte: date('2024-06-01T00:00:00Z') } } }],
    check: { action: 'read', subject: of_('A', { at: date('2024-01-01T00:00:00Z') }) },
  },
  {
    // D-12
    id: 'op/gt-string-vs-number',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { x: { $gt: 3 } } }],
    check: { action: 'read', subject: of_('A', { x: '10' }) },
    deviates: {
      dart: false,
      reason:
        'JavaScript coerces across types, so `"10" > 3` is true. `caslCompare` '
        + 'refuses to order values it cannot compare and returns -1, so the rule '
        + 'denies. A condition comparing a string to a number is a mistake, and '
        + 'denying is the safe reading of a mistake in an authorisation library. '
        + 'See docs/PARITY.md D-12.',
    },
  },
  {
    id: 'op/in-scalar',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { s: { $in: ['review', 'published'] } } }],
    check: { action: 'read', subject: of_('A', { s: 'review' }) },
  },
  {
    id: 'op/in-array-intersection',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { c: { $in: ['js', 'fe'] } } }],
    check: { action: 'read', subject: of_('A', { c: ['js', 'acl'] }) },
  },
  {
    id: 'op/nin',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { s: { $nin: ['draft'] } } }],
    check: { action: 'read', subject: of_('A', { s: 'published' }) },
  },
  {
    id: 'op/in-nested-array-value',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { t: { $in: [['a']] } } }],
    check: { action: 'read', subject: of_('A', { t: ['a'] }) },
  },
  {
    // D-10
    id: 'op/in-regex-element',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { t: { $in: [re('^ab')] } } }],
    check: { action: 'read', subject: of_('A', { t: 'abc' }) },
  },
  {
    id: 'op/all',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { t: { $all: ['x', 'y'] } } }],
    check: { action: 'read', subject: of_('A', { t: ['y', 'x', 'z'] }) },
  },
  {
    id: 'op/all-missing-one',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { t: { $all: ['x', 'q'] } } }],
    check: { action: 'read', subject: of_('A', { t: ['x', 'y'] }) },
  },
  {
    id: 'op/size',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { t: { $size: 2 } } }],
    check: { action: 'read', subject: of_('A', { t: [1, 2] }) },
  },
  {
    // D-08
    id: 'op/size-nested-array-path',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { 'items.tags': { $size: 2 } } }],
    check: {
      action: 'read',
      subject: of_('A', { items: [{ tags: [1, 2] }, { tags: [3] }] }),
    },
  },
  {
    id: 'op/regex-string',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { e: { $regex: '@gmail.com$' } } }],
    check: { action: 'read', subject: of_('A', { e: 'a@gmail.com' }) },
  },
  {
    id: 'op/regex-options-i',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { t: { $regex: '^draft', $options: 'i' } } }],
    check: { action: 'read', subject: of_('A', { t: 'DRAFT x' }) },
  },
  {
    // D-09
    id: 'op/regex-options-g',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { x: { $regex: 'ab', $options: 'g' } } }],
    check: { action: 'read', subject: of_('A', { x: 'abc' }) },
  },
  {
    id: 'op/regex-non-string-field',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { x: { $regex: 'ab' } } }],
    check: { action: 'read', subject: of_('A', { x: 42 }) },
  },
  {
    id: 'op/exists-true',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { b: { $exists: true } } }],
    check: { action: 'read', subject: of_('A', { b: 1 }) },
  },
  {
    id: 'op/exists-true-null-value',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { b: { $exists: true } } }],
    check: { action: 'read', subject: of_('A', { b: null }) },
  },
  {
    id: 'op/exists-false',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { b: { $exists: false } } }],
    check: { action: 'read', subject: of_('A', {}) },
  },
  {
    id: 'op/exists-nested-missing-parent',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { 'a.b': { $exists: true } } }],
    check: { action: 'read', subject: of_('A', {}) },
  },
  {
    id: 'op/elem-match-object',
    op: 'can',
    rules: [{
      action: 'update',
      subject: 'A',
      conditions: { shared: { $elemMatch: { permission: 'update', userId: 1 } } },
    }],
    check: {
      action: 'update',
      subject: of_('A', {
        shared: [{ permission: 'read', userId: 2 }, { permission: 'update', userId: 1 }],
      }),
    },
  },
  {
    id: 'op/elem-match-splits-across-elements',
    op: 'can',
    rules: [{
      action: 'update',
      subject: 'A',
      conditions: { shared: { $elemMatch: { permission: 'update', userId: 1 } } },
    }],
    check: {
      action: 'update',
      subject: of_('A', {
        shared: [{ permission: 'update', userId: 2 }, { permission: 'read', userId: 1 }],
      }),
    },
  },
  {
    id: 'op/elem-match-scalars',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { scores: { $elemMatch: { $gte: 80 } } } }],
    check: { action: 'read', subject: of_('A', { scores: [10, 90] }) },
  },

  // ------------------------------------------------------- operator handling
  {
    // D-06
    id: 'parser/toplevel-or-unsupported',
        op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { $or: [{ x: 1 }, { y: 2 }] } }],
    check: { action: 'read', subject: of_('A', { x: 1 }) },
    deviates: {
      dart: { '!throws': true },
      reason:
        'CASL.js only routes a value into the operator path when it recognises '
        + 'a key, so an operator it has never heard of silently becomes an '
        + 'equality test against a literal map and quietly matches nothing. We '
        + 'refuse instead: a rule nobody can evaluate must not be read as a '
        + 'rule that simply does not apply. Pass '
        + '`onUnparsableCondition: UnparsableCondition.deny` for a client whose '
        + 'server may know operators it does not. See docs/PARITY.md D-06.',
    },
  },
  {
    // D-06
    id: 'parser/unknown-field-operator',
        op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { x: { $mod: [2, 0] } } }],
    check: { action: 'read', subject: of_('A', { x: 4 }) },
    deviates: {
      dart: { '!throws': true },
      reason:
        'CASL.js only routes a value into the operator path when it recognises '
        + 'a key, so an operator it has never heard of silently becomes an '
        + 'equality test against a literal map and quietly matches nothing. We '
        + 'refuse instead: a rule nobody can evaluate must not be read as a '
        + 'rule that simply does not apply. Pass '
        + '`onUnparsableCondition: UnparsableCondition.deny` for a client whose '
        + 'server may know operators it does not. See docs/PARITY.md D-06.',
    },
  },
  {
    // D-07
    id: 'parser/operator-mixed-with-plain-key',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { x: { stray: 2, $gt: 1 } } }],
    check: { action: 'read', subject: of_('A', { x: 5 }) },
  },
  {
    id: 'parser/plain-nested-object-is-a-value',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { x: { a: 1 } } }],
    check: { action: 'read', subject: of_('A', { x: { a: 1 } }) },
    deviates: {
      dart: true,
      reason:
        'The condition engine CASL.js delegates to compares with `===`, so it '
        + 'structurally cannot match a nested object or a whole array by value. '
        + 'We compare by value, which is what MongoDB itself does. Pass '
        + '`strictJsEquality: true` for bug-compatibility. See docs/PARITY.md D-01.',
    },
  },

  // ----------------------------------------------- type versus instance rules
  {
    id: 'asymmetry/direct-rule-vs-type',
    op: 'can',
    rules: [{ action: 'update', subject: 'A', conditions: { authorId: 1 } }],
    check: { action: 'update', subject: 'A' },
  },
  {
    id: 'asymmetry/inverted-rule-vs-type',
    op: 'can',
    rules: [
      { action: 'update', subject: 'A' },
      { action: 'update', subject: 'A', conditions: { locked: true }, inverted: true },
    ],
    check: { action: 'update', subject: 'A' },
  },
  {
    id: 'asymmetry/inverted-unconditional-vs-type',
    op: 'can',
    rules: [
      { action: 'update', subject: 'A' },
      { action: 'update', subject: 'A', inverted: true },
    ],
    check: { action: 'update', subject: 'A' },
  },

  // ------------------------------------------------------------------ fields
  {
    id: 'field/allowed',
    op: 'can',
    rules: [{ action: 'update', subject: 'A', fields: ['title', 'body'] }],
    check: { action: 'update', subject: 'A', field: 'title' },
  },
  {
    id: 'field/not-listed',
    op: 'can',
    rules: [{ action: 'update', subject: 'A', fields: ['title'] }],
    check: { action: 'update', subject: 'A', field: 'published' },
  },
  {
    id: 'field/inverted-ignored-when-asking-any',
    op: 'can',
    rules: [
      { action: 'read', subject: 'A' },
      { action: 'read', subject: 'A', fields: ['secret'], inverted: true },
    ],
    check: { action: 'read', subject: 'A' },
  },
  {
    id: 'field/inverted-blocks-that-field',
    op: 'can',
    rules: [
      { action: 'read', subject: 'A' },
      { action: 'read', subject: 'A', fields: ['secret'], inverted: true },
    ],
    check: { action: 'read', subject: 'A', field: 'secret' },
  },
  {
    id: 'field/on-fieldless-rule',
    op: 'can',
    rules: [{ action: 'read', subject: 'A' }],
    check: { action: 'read', subject: 'A', field: 'anything' },
  },
  {
    id: 'field/wildcard-single-segment',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', fields: ['address.*'] }],
    check: { action: 'read', subject: 'A', field: 'address.city' },
  },
  {
    id: 'field/wildcard-single-segment-does-not-cross-dot',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', fields: ['address.*'] }],
    check: { action: 'read', subject: 'A', field: 'address.geo.lat' },
  },
  {
    id: 'field/wildcard-double-crosses-dots',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', fields: ['address.**'] }],
    check: { action: 'read', subject: 'A', field: 'address.geo.lat' },
  },
  {
    id: 'field/wildcard-matches-bare-parent',
    op: 'can',
    rules: [{ action: 'read', subject: 'A', fields: ['address.*'] }],
    check: { action: 'read', subject: 'A', field: 'address' },
  },

  // --------------------------------------------------------- permittedFields
  {
    id: 'permitted/basic',
    op: 'fields',
    rules: [
      { action: 'update', subject: 'A', fields: ['title', 'description'] },
      { action: 'update', subject: 'A', fields: ['published'], inverted: true },
    ],
    action: 'update',
    subject: 'A',
    allFields: ['title', 'description', 'published'],
  },
  {
    // D-14
    id: 'permitted/wildcard-expansion',
    op: 'fields',
    rules: [{ action: 'read', subject: 'A', fields: ['address.*'] }],
    action: 'read',
    subject: 'A',
    allFields: ['title', 'address.city'],
    deviates: {
      dart: ['address.city'],
      reason:
        'CASL.js hands back the rule pattern verbatim. We resolve it against '
        + '`allFields`, because the caller asked which fields to render and a '
        + 'pattern is not a field. See docs/PARITY.md D-14.',
    },
  },
  {
    // D-14
    id: 'permitted/ordering',
    op: 'fields',
    rules: [
      { action: 'read', subject: 'A', fields: ['b'] },
      { action: 'read', subject: 'A', fields: ['a'] },
    ],
    action: 'read',
    subject: 'A',
    allFields: ['a', 'b'],
    deviates: {
      dart: ['a', 'b'],
      reason:
        'CASL.js returns fields in the order the rules happened to mention '
        + 'them. We return them in `allFields` order, because this drives a '
        + 'form and a form\'s field order is a design decision, not an '
        + 'accident of rule authoring. See docs/PARITY.md D-14.',
    },
  },
  {
    id: 'permitted/conditions-against-instance',
    op: 'fields',
    rules: [{ action: 'update', subject: 'A', fields: ['title'], conditions: { authorId: 1 } }],
    action: 'update',
    subject: of_('A', { authorId: 2 }),
    allFields: ['title', 'body'],
  },

  // ------------------------------------------------------------ rulesToFields
  {
    id: 'defaults/plain-values',
    op: 'defaults',
    rules: [
      { action: 'create', subject: 'A', conditions: { status: 'draft', authorId: 1 } },
    ],
    action: 'create',
    subjectType: 'A',
  },
  {
    id: 'defaults/skips-operators-and-inverted',
    op: 'defaults',
    rules: [
      { action: 'create', subject: 'A', conditions: { tags: ['x'], n: 0, s: { $in: [1] } } },
      { action: 'create', subject: 'A', conditions: { secret: true }, inverted: true },
    ],
    action: 'create',
    subjectType: 'A',
  },
  {
    id: 'defaults/dotted-path-nests',
    op: 'defaults',
    rules: [{ action: 'create', subject: 'A', conditions: { 'a.b': 1 } }],
    action: 'create',
    subjectType: 'A',
  },

  // ----------------------------------------------------------------- rulesToAST
  {
    id: 'ast/can-and-cannot',
    op: 'ast',
    rules: [
      { action: 'read', subject: 'A', conditions: { x: 1 } },
      { action: 'read', subject: 'A', conditions: { y: 2 }, inverted: true },
    ],
    action: 'read',
    subjectType: 'A',
  },
  {
    id: 'ast/nothing-permitted',
    op: 'ast',
    rules: [{ action: 'read', subject: 'A', conditions: { x: 1 }, inverted: true }],
    action: 'read',
    subjectType: 'A',
  },
  {
    id: 'ast/unconditional-can-is-unrestricted',
    op: 'ast',
    rules: [{ action: 'read', subject: 'A' }],
    action: 'read',
    subjectType: 'A',
  },
  {
    id: 'ast/unconditional-cannot-stops-the-walk',
    op: 'ast',
    rules: [
      { action: 'read', subject: 'A', inverted: true },
      { action: 'read', subject: 'A', conditions: { x: 1 } },
    ],
    action: 'read',
    subjectType: 'A',
  },
  {
    id: 'ast/two-permitting-branches',
    op: 'ast',
    rules: [
      { action: 'read', subject: 'A', conditions: { x: 1 } },
      { action: 'read', subject: 'A', conditions: { y: 2 } },
    ],
    action: 'read',
    subjectType: 'A',
  },
  {
    // D-03: a duplicated rule shows up here as a duplicated OR branch.
    id: 'ast/no-duplicate-branch-from-wildcard-action',
    op: 'ast',
    rules: [{ action: ['read', 'manage'], subject: 'A', conditions: { x: 1 } }],
    action: 'read',
    subjectType: 'A',
  },

  // ------------------------------------------------------------------ packing
  {
    // D-13
    id: 'pack/claim-rule',
    op: 'pack',
    rules: [{ action: 'read' }],
    deviates: {
      dart: [['read', 'all']],
      reason:
        '`RawRule` normalises a missing subject to `all`, so a claim-style rule '
        + 'packs with a slot CASL.js drops. Both unpack to the same ability and '
        + 'a CASL.js server indexes them identically, so tracking whether the '
        + 'subject was written down would be state carried for a cosmetic '
        + 'difference. See docs/PARITY.md D-13.',
    },
  },
  {
    id: 'pack/full-rule',
    op: 'pack',
    rules: [{
      action: ['a', 'b'],
      subject: 'S',
      conditions: { x: 1 },
      inverted: true,
      fields: ['f'],
      reason: 'r',
    }],
  },
  {
    id: 'pack/reason-only-keeps-placeholders',
    op: 'pack',
    rules: [{ action: 'a', subject: 'S', reason: 'r' }],
  },
  {
    id: 'pack/trailing-empties-dropped',
    op: 'pack',
    rules: [{ action: 'a', subject: 'S' }],
  },
  {
    id: 'pack/multiple-subjects',
    op: 'pack',
    rules: [{ action: 'read', subject: ['A', 'B'] }],
  },

  // ------------------------------------------------- unparsable-condition policy
  //
  // `deny: true` builds the Dart ability with
  // `onUnparsableCondition: UnparsableCondition.deny` and expects CASL.js's
  // answer exactly. CASL.js never throws on an unknown operator, so agreeing
  // with it here *is* the proof that the escape hatch works.
  {
    id: 'deny/toplevel-or',
    deny: true,
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { $or: [{ x: 1 }, { y: 2 }] } }],
    check: { action: 'read', subject: of_('A', { x: 1 }) },
  },
  {
    id: 'deny/unknown-field-operator',
    deny: true,
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { x: { $mod: [2, 0] } } }],
    check: { action: 'read', subject: of_('A', { x: 4 }) },
  },
  {
    // Denying one rule must not deny the rules beside it.
    id: 'deny/other-rules-survive',
    deny: true,
    op: 'can',
    rules: [
      { action: 'read', subject: 'A', conditions: { $or: [{ x: 1 }] } },
      { action: 'read', subject: 'A', conditions: { x: 1 } },
    ],
    check: { action: 'read', subject: of_('A', { x: 1 }) },
  },
  {
    id: 'deny/known-operators-still-work',
    deny: true,
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { n: { $gte: 3 } } }],
    check: { action: 'read', subject: of_('A', { n: 4 }) },
  },

  // ------------------------------------------------------------ strict mode
  //
  // `strict: true` builds the Dart ability with `strictJsEquality: true` and
  // expects CASL.js's answer *exactly* — no deviation permitted. JavaScript is
  // always strict, so nothing changes on the recording side.
  //
  // These are the D-01 cases again, and they are the proof that the escape
  // hatch works: without them `strictJsEquality` would be a claim in a doc
  // comment rather than a tested behaviour.
  {
    id: 'strict/eq-object-value',
    strict: true,
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { meta: { x: 1 } } }],
    check: { action: 'read', subject: of_('A', { meta: { x: 1 } }) },
  },
  {
    id: 'strict/eq-array-value',
    strict: true,
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { tags: ['a', 'b'] } }],
    check: { action: 'read', subject: of_('A', { tags: ['a', 'b'] }) },
  },
  {
    id: 'strict/plain-nested-object-is-a-value',
    strict: true,
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { x: { a: 1 } } }],
    check: { action: 'read', subject: of_('A', { x: { a: 1 } }) },
  },
  {
    // Strict mode must not disturb the ordinary cases it shares code with.
    id: 'strict/scalar-still-matches',
    strict: true,
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { authorId: 7 } }],
    check: { action: 'read', subject: of_('A', { authorId: 7 }) },
  },
  {
    id: 'strict/in-still-matches',
    strict: true,
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { s: { $in: ['a', 'b'] } } }],
    check: { action: 'read', subject: of_('A', { s: 'b' }) },
  },
  {
    id: 'strict/date-compares-by-instant',
    strict: true,
    op: 'can',
    rules: [{ action: 'read', subject: 'A', conditions: { at: date('2024-01-01T00:00:00Z') } }],
    check: { action: 'read', subject: of_('A', { at: date('2024-01-01T00:00:00Z') }) },
  },
];
