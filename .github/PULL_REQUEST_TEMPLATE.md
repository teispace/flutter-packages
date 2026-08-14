<!--
Thanks for this. The checklist is short on purpose — everything on it is
something a reviewer would otherwise have to ask for.
-->

## What this changes

<!-- One or two sentences. What behaviour is different after this lands? -->

## Why

<!--
The reasoning, not the diff. If it fixes an issue, "Fixes #123" is enough.
If it changes what a rule means, say so here in as many words — that is the
thing a reviewer most needs to see and the easiest to miss in a diff.
-->

## Type of change

- [ ] Bug fix — behaviour was wrong
- [ ] Parity fix — we now agree with `@casl/ability` where we did not
- [ ] Deliberate deviation from `@casl/ability` (record it in the parity ledger)
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation
- [ ] Internal — no behaviour change

## Checklist

- [ ] **`melos run ci` is green locally.** Same pipeline CI runs.
- [ ] **There is a test that fails without this change.** Not just a test — the
      one that would have caught it.
- [ ] `CHANGELOG.md` updated under `## Unreleased`, in the package changed.
      Do not bump `version:`; that happens at release.
- [ ] Every new public member is documented. `public_member_api_docs` enforces
      it, but write it for a reader rather than for the linter.
- [ ] Commit messages follow Conventional Commits, scoped: `fix(casl): …`.

## If this touches authorisation behaviour

<!-- Delete this section if it does not. -->

- [ ] The parity fixture set was regenerated, and the diff is in this PR.
- [ ] The change makes us **no more permissive** than `@casl/ability`, or if it
      does, that is stated here with the reason.
- [ ] Any intentional deviation is recorded with its reasoning, so the next
      maintainer does not have to rediscover it.

**Which direction does this move us?**

<!--
"More permissive", "more restrictive", or "no change to any outcome".
A permissive change is the one that gets read twice, because a client that
allows what a server refuses is the exact failure these packages exist to
prevent.
-->
