// Runs every case in cases.mjs through the real @casl/ability and records what
// it answered. The Dart suite replays the recording.
//
// Nothing here is clever on purpose: the value of a golden file is that you can
// read the diff and believe it.

import { writeFileSync, mkdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { createMongoAbility, subject } from '@casl/ability';
import {
  packRules,
  permittedFieldsOf,
  rulesToFields,
  rulesToAST,
} from '@casl/ability/extra';

import { cases } from './cases.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, '../../packages/casl/test/fixtures/parity.json');
const caslVersion = JSON.parse(
  readFileSync(join(here, 'node_modules/@casl/ability/package.json'), 'utf8'),
).version;

const ITSELF = '__itself__';

// --------------------------------------------------------------- value codec

/** Turns the JSON-safe markers in a case into the real values CASL wants. */
function decode(value) {
  if (value === null || typeof value !== 'object') return value;
  if (Array.isArray(value)) return value.map(decode);
  if ('!re' in value) return new RegExp(value['!re'], value.flags || '');
  if ('!date' in value) return new Date(value['!date']);

  const result = {};
  for (const [k, v] of Object.entries(value)) result[k] = decode(v);
  return result;
}

/** The inverse, for anything that ends up in the recorded output. */
function encode(value) {
  if (value === null || value === undefined) return value ?? null;
  if (value instanceof RegExp) return { '!re': value.source, flags: value.flags };
  if (value instanceof Date) return { '!date': value.toISOString() };
  if (Array.isArray(value)) return value.map(encode);
  if (typeof value !== 'object') return value;

  const result = {};
  for (const [k, v] of Object.entries(value)) result[k] = encode(v);
  return result;
}

/** A case's `subject` field: either a bare type, or `of_(type, value)`. */
function asSubject(spec) {
  if (spec === undefined || spec === null) return undefined;
  if (typeof spec === 'string') return spec;
  return subject(spec.type, decode(spec.value));
}

// ------------------------------------------------------------------ AST shape

/**
 * A canonical form both implementations can produce.
 *
 * ucast distinguishes compound from field conditions by whether a `field`
 * property exists; its field-less marker is the string `__itself__`, which we
 * normalise to null so Dart's `null` compares equal.
 */
function canonicalAst(node) {
  if (node === null || node === undefined) return null;

  if ('field' in node) {
    return {
      op: node.operator,
      field: node.field === ITSELF ? null : node.field,
      value: node.value && typeof node.value === 'object' && 'operator' in node.value
        ? canonicalAst(node.value)          // $elemMatch holds a nested condition
        : encode(node.value),
    };
  }

  return {
    op: node.operator,
    children: (node.value ?? []).map(canonicalAst),
  };
}

// ------------------------------------------------------------------- runners

const run = {
  can(c, ability) {
    return ability.can(c.check.action, asSubject(c.check.subject), c.check.field);
  },

  rules(c, ability) {
    return ability.possibleRulesFor(c.action, c.subjectType).length;
  },

  actions(c, ability) {
    return ability.actionsFor(c.subjectType).sort();
  },

  ast(c, ability) {
    return canonicalAst(rulesToAST(ability, c.action, c.subjectType));
  },

  defaults(c, ability) {
    return encode(rulesToFields(ability, c.action, c.subjectType));
  },

  fields(c, ability) {
    return permittedFieldsOf(ability, c.action, asSubject(c.subject), {
      fieldsFrom: (rule) => rule.fields || c.allFields,
    });
  },

  pack(c) {
    return encode(packRules(c.rules.map(decode)));
  },
};

// ---------------------------------------------------------------------- main

const results = [];
const seen = new Set();

for (const c of cases) {
  if (seen.has(c.id)) throw new Error(`duplicate case id: ${c.id}`);
  seen.add(c.id);

  const runner = run[c.op];
  if (!runner) throw new Error(`${c.id}: unknown op "${c.op}"`);

  if (c.deviates && !c.deviates.reason) {
    throw new Error(`${c.id}: a deviation must carry a reason`);
  }
  if (c.deviates && c.pending) {
    throw new Error(
      `${c.id}: cannot be both a settled deviation and pending work`,
    );
  }
  if (c.deny && (c.deviates || c.pending)) {
    throw new Error(
      `${c.id}: a deny case exists to prove exact agreement, so it cannot `
      + 'also record a difference',
    );
  }
  if (c.strict && (c.deviates || c.pending)) {
    throw new Error(
      `${c.id}: a strict case exists to prove exact agreement, so it cannot `
      + 'also record a difference',
    );
  }

  // The ability is built inside the try: an unsupported operator throws at
  // construction time, not at check time, and that is itself a recorded
  // behaviour rather than a harness failure.
  let expected;
  try {
    expected = runner(c, createMongoAbility(c.rules.map(decode)));
  } catch {
    expected = { '!throws': true };
  }

  results.push({
    id: c.id,
    op: c.op,
    rules: c.rules,
    ...(c.check !== undefined && { check: c.check }),
    ...(c.action !== undefined && { action: c.action }),
    ...(c.subject !== undefined && { subject: c.subject }),
    ...(c.subjectType !== undefined && { subjectType: c.subjectType }),
    ...(c.allFields !== undefined && { allFields: c.allFields }),
    expected,
    // JavaScript is always strict, so this changes nothing here — it tells the
    // Dart side to build with `strictJsEquality: true` and match exactly.
    ...(c.strict && { strict: true }),
    // CASL.js never throws on an unknown operator, so this changes nothing
    // here either — it tells the Dart side to tolerate rather than fail.
    ...(c.deny && { deny: true }),
    ...(c.deviates && { deviates: c.deviates }),
    ...(c.pending && { pending: c.pending }),
  });
}

mkdirSync(dirname(out), { recursive: true });
writeFileSync(
  out,
  `${JSON.stringify(
    {
      // Deliberately not a timestamp: this file is regenerated in CI and
      // compared against the committed copy, so anything that changes on every
      // run would make that check useless.
      generatedBy: 'tool/parity/generate.mjs',
      reference: `@casl/ability@${caslVersion}`,
      cases: results,
    },
    null,
    2,
  )}\n`,
);

const deviations = results.filter((r) => r.deviates).length;
const pending = results.filter((r) => r.pending);
const matching = results.length - deviations - pending.length;

console.log(`${results.length} cases against @casl/ability@${caslVersion}`);
console.log(`  ${matching} expected to match`);
console.log(`  ${deviations} settled deviations`);
console.log(`  ${pending.length} pending — known divergences not yet resolved`);

if (pending.length) {
  const byFinding = {};
  for (const c of pending) (byFinding[c.pending] ??= []).push(c.id);
  for (const [finding, ids] of Object.entries(byFinding).sort()) {
    console.log(`    ${finding}: ${ids.join(', ')}`);
  }
}

console.log(`→ ${out}`);
