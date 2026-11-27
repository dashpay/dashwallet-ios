# 0074 — Report a kept response from the write point, or from the same predicate when the lookup fails

- **Status:** Proposed
- **Date:** 2026-11-23
- **Deciders:** romchornyi (ADR author)

## Context

[ADR-0052](0052-refuse-response-removed-at-its-one-write-point-while-the-publish-is-unresolved.md)
makes `markResponseRemoved` the one write point of "response removed" and has it refuse while the
publish is unresolved (`AppConnect.isPublishUnresolved`, ADR-0050). It also says callers report
the refusal instead of re-checking, so the disconnect's "response may still appear" never comes
from a second evaluation.

That holds when a lookup answers. It does not when the lookup fails: `deleteResponses` tries the
lookup twice, and when both throw it writes nothing, asks `AppConnect.isPublishUnresolved` itself
and reports the intent as kept when the publish is unresolved. The write point is never asked, because there is nothing to
write. The guard of ADR-0052 still holds on every path; only its account of where the note comes
from is wrong. The review of #1447 found it.

## Decision drivers

- No operation records a response removed while its publish is unresolved (ADR-0052, spec AC-03).
- The disconnect must tell the user when its own app's response may still appear (ADR-0052,
  spec AC-02), also when Platform could not be asked.
- A failed lookup says nothing about the response, so it must not be read as "none".

## Considered options

1. **Two sources for the note, one predicate.** `markResponseRemoved` stays the one write point
   and refuses while the publish is unresolved. A caller reports its refusal when a lookup found
   no response. When the lookup fails twice, nothing is written, and `deleteResponses` reports
   the intent as kept when `AppConnect.isPublishUnresolved` holds at the same Platform block time.
2. **Route a failed lookup through the write point.** Call `markResponseRemoved` after a failed
   lookup too. It would record the response removed once the publish is resolved, although no
   lookup has shown it gone.

## Decision outcome

**Chosen:** option 1. A failed lookup writes nothing, so it has no write point to ask; the note
it gives is decided by the same pure predicate with the same block time the write point uses.

- `markResponseRemoved` remains the only code that sets `responseRemoved` to `true`, and it refuses while
  the publish is unresolved.
- After a lookup that found no response, and after a failed delete whose lookup shows none,
  callers report the write point's `.kept`.
- After two failed lookups, `deleteResponses` writes nothing and reports the intent as kept when
  `AppConnect.isPublishUnresolved(_:platformTime:)` holds.
- Only the disconnected app's own kept intents set the disconnect's note.

## Consequences

**Positive**
- The guard of ADR-0052 is unchanged: a new path still cannot record a response removed while
  its publish is unresolved.
- When both lookups fail and the publish is still unresolved, a disconnect that returns its
  result still warns that the response may appear. Once the publish is resolved (48 hours of
  proved Platform block time, ADR-0050), the failed lookups give no warning.

**Negative**
- The note has two sources. They share the predicate and the block time, but a change to one
  path must be checked against the other.
- Not every disconnect can give the note. One whose key updates stopped (an update to add fences
  or turn keys off that is not known to have landed), or one with nothing to sign, does not look
  responses up; a fence that fails to turn off afterwards does not stop it. One that ends with
  `identityKeysOutOfDate` or `grantOnAnotherIdentity` may or may not have looked them up, and
  either error replaces its result and any note with it.

**Neutral**
- A response whose lookups failed stays not removed; once its intent is closed, the next approval
  on the identity whose read of the identity after it succeeds looks it up again
  (`AppConnect.responsesLeft`; when that read fails, the approval ends without looking), and so
  does the next disconnect there that has something to sign and whose key updates do not stop.

## Links

- Supersedes [ADR-0052](0052-refuse-response-removed-at-its-one-write-point-while-the-publish-is-unresolved.md).
- Related ADR: [0050](0050-bound-an-unresolved-publish-by-48-hours-of-proved-platform-block-time.md)
- Feature summary: [docs/features/app-connect/README.md](../features/app-connect/README.md)
- Found in the review of #1447.
