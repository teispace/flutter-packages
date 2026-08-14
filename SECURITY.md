# Security policy

`casl` and `casl_flutter` decide what a user is allowed to do. A defect in
either can mean an application shows a control, or permits an operation, that it
should have refused. We treat those as security issues, not ordinary bugs.

## Please do not open a public issue

A public report describing an authorisation bypass is a working exploit for
every application that has already shipped the affected version — and unlike a
server-side library, a Flutter app cannot be patched by its maintainer. Its
users have to update it.

## How to report

**Preferred — GitHub private vulnerability reporting.** Go to the
[Security tab](https://github.com/teispace/flutter-packages/security/advisories/new)
and open a draft advisory. It is private, it threads, and it produces a CVE and
a published advisory at the end without anyone re-keying the details.

**Alternative — email.** <info@teispace.com>, with `SECURITY` in the subject. If
you would like to encrypt, say so in a first message and we will exchange keys.

## What to include

The more of this you have, the faster the fix:

- The package and version (`casl 0.1.0`), and the Dart or Flutter SDK version.
- The **rules** involved — the smallest set that reproduces it.
- The subject and the check: what you called, what it returned, what it should
  have returned.
- Whether the divergence is *permissive* (allows something it should refuse) or
  *restrictive* (refuses something it should allow). Permissive is urgent;
  restrictive is a bug.
- Whether a CASL.js server would have decided differently on the same rules. A
  client that disagrees with its server is the failure mode this package exists
  to prevent, and knowing which side is wrong shapes the fix.

A failing test is the ideal report and very often the fastest fix.

## What happens next

| | |
|---|---|
| Acknowledgement | within 3 working days |
| Initial assessment, with a severity and a rough timeline | within 7 days |
| Fix released | as fast as the severity warrants — a permissive bypass is treated as urgent |

We will keep you updated while it is open, credit you in the advisory and the
changelog unless you would rather we did not, and tell you when it is published.

## Scope

**In scope** — anything that makes a permission check produce the wrong answer:

- A check that permits where the rules forbid, or forbids where they permit.
- A divergence from `@casl/ability` that changes an authorisation outcome, in
  either direction.
- A rule payload from a server that crashes the client, hangs it, or is parsed
  into different rules than were sent.
- Anything in `casl_flutter` that renders a control the ability refuses.

**Out of scope** — real bugs, but not security issues; please open a normal
issue for these:

- Documentation errors, unless the documented pattern is itself insecure.
- Deliberate deviations from CASL.js that are recorded in the parity ledger and
  the README. If you think one of them is *wrong*, that is in scope — say so.
- Weaknesses in an application's own rules. This library evaluates the rules it
  is given; deciding they are the right rules is the application's job.

## Supported versions

| Version | Supported |
|---|---|
| 0.1.x | ✅ |

Pre-1.0, security fixes land on the latest minor. Once 1.0 ships, this table
will name a maintenance window.

## A note on the threat model

Rules evaluated on a client are a **user-experience** control, not an
enforcement boundary. Anyone can modify a client binary and answer `true` to
every check. The server must enforce the same rules independently — which is
the reason this package is wire-compatible with `@casl/ability` rather than
inventing its own format.

A report that amounts to "I patched the app and bypassed a check" is expected
behaviour, not a vulnerability. A report that the *same rules* are evaluated
differently here than on the server is exactly what we want to hear about.
