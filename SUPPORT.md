# Getting help

## Where to go

| You want to | Go to |
|---|---|
| Ask how to do something | [Discussions → Q&A](https://github.com/teispace/flutter-packages/discussions/categories/q-a) |
| Report something broken | [Issues](https://github.com/teispace/flutter-packages/issues/new/choose) |
| Report a permission check giving the wrong answer | [Security policy](./SECURITY.md) — not a public issue |
| Report a difference from `@casl/ability` | [Issues → Parity gap](https://github.com/teispace/flutter-packages/issues/new/choose) |
| Suggest a feature | [Discussions → Ideas](https://github.com/teispace/flutter-packages/discussions/categories/ideas) first, so it can be talked through before anyone writes code |
| Understand CASL itself — rules, conditions, precedence | [casl.js.org](https://casl.js.org/v7/en/guide/intro). The model is identical; only the syntax differs |

Issues are for defects and tracked work. Questions get better answers in
Discussions, where they stay findable for the next person with the same
question.

## Before you ask

Most questions turn out to be one of these four. Checking takes a minute and
often answers it outright.

**1. Is it the precedence rule?**
The **last matching rule wins** — not "cannot beats can". Writing `cannot` and
then `can` *permits*. This is deliberate, it is what makes rule sets
composable, and it surprises nearly everyone once.

**2. Are you asking about a type or an instance?**
`can('update', 'Article')` asks *"is there any article I may update?"* —
conditions cannot be evaluated without an instance, so a permitting rule with
conditions answers **yes**. `can('update', article)` asks about that one
article and evaluates them. Both are correct answers to different questions.

**3. Is the subject type what you think it is?**
Without `CaslSubject` or `subject()`, the type is `runtimeType.toString()` —
which is wrong under `--obfuscate`, in release builds only. If a check passes in
debug and fails in release, this is why. `ability.detectSubjectType(x)` will
tell you what it actually resolved to.

**4. Which rule decided?**
`ability.relevantRuleFor(action, subject, field)` returns the rule that produced
the answer, or `null` when nothing matched. Its `conditions`, `fields` and
`inverted` usually make the reason obvious immediately.

## What makes a good question

- The **rules**, as code. Not a description of them — the smallest set that
  reproduces the behaviour.
- The **check** and what you expected: `ability.can('update', article)` returned
  `false`, expected `true`.
- The package version, and the Dart or Flutter version.
- If a CASL.js server is involved: what it decides on the same rules.

A snippet someone can paste into a test gets an answer far faster than a
description, because the first thing anyone will do is try to reproduce it.

## Response times

This is maintained alongside other work. Expect a few days for questions and
ordinary bugs. Security reports are handled on the timeline in
[SECURITY.md](./SECURITY.md), which is much shorter.

If something has gone quiet for a couple of weeks, a nudge on the thread is
welcome rather than rude.
