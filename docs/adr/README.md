# Decision log

The architecture decision records (ADRs) of dashwallet-ios, governed by
[ADR-0001](0001-record-architecture-decisions-as-adrs.md). It lists every log ADR under its log
number, never a feature-local number, and is kept by hand. The notes below summarize ADR-0001;
where they disagree, ADR-0001 wins.

| # | Title | Area | Status | Superseded by |
|---|---|---|---|---|
| [0001](0001-record-architecture-decisions-as-adrs.md) | Record architecture decisions as ADRs | process | Accepted | |
| [0002](0002-keep-the-decision-log-in-docs-adr.md) | Keep the decision log in docs/adr | process | Accepted | |
| [0003](0003-take-rust-toolchain-from-platform-pin.md) | Take the Rust toolchain version from platform's pin | build | Accepted | |
| [0004](0004-read-xcode-version-file-via-composite-action.md) | Read the Xcode version from a file through a composite action | build | Accepted | |
| [0005](0005-enforce-workflow-policy-with-in-repo-script.md) | Enforce workflow policy with an in-repo script beside actionlint | build | Accepted | |
| [0006](0006-choose-the-app-connect-login-by-the-protocol-version-read-at-runtime.md) | Choose the App Connect login by the protocol version read at runtime | platform | Proposed | |
| [0007](0007-call-a-payment-links-sender-back-only-when-another-app-opened-the-link.md) | Call a payment link's sender back only when another app opened the link | payments | Proposed | |
| [0009](0009-answer-app-connect-request-v2-with-wallet-derived-keys-under-wallet-limits.md) | Answer App Connect request v2 with wallet-derived keys under wallet limits | platform | Proposed | |
| [0023](0023-remove-crowdnode-entirely-as-android-does.md) | Remove CrowdNode entirely, as Android does | ui | Proposed | |
| [0024](0024-pin-shortcut-raw-values-and-refill-the-retired-slot.md) | Pin shortcut raw values and refill the retired slot | ui | Proposed | |
| [0025](0025-remove-crowdnode-defaults-by-exact-key-list-on-activation.md) | Remove CrowdNode defaults by exact key list on activation | storage | Proposed | |
| [0026](0026-retire-the-crowdnode-topic-by-marking-events-seen.md) | Retire the CrowdNode topic by marking its events seen | storage | Proposed | |
| [0031](0031-turn-off-unattributed-dashpay-profile-keys-with-any-disconnect.md) | Turn off unattributed DashPay profile keys with any disconnect | keys | Proposed | |
| [0036](0036-ship-the-ios-screens-and-the-sdk-binding-as-two-surfaces.md) | Ship the iOS screens and the SDK binding as two surfaces | platform | Proposed | |
| [0037](0037-build-external-send-as-a-new-module-over-the-existing-spend-seams.md) | Build external send as a new module over the existing spend seams | payments | Proposed | |
| [0038](0038-decide-every-source-and-destination-pair-in-one-policy.md) | Decide every source and destination pair in one policy | payments | Proposed | |
| [0039](0039-estimate-the-fee-on-send-and-recompute-it-on-confirm.md) | Estimate the fee on Send and recompute it on Confirm | payments | Proposed | |
| [0040](0040-report-three-send-outcomes-and-retry-only-when-nothing-left-the-source.md) | Report three send outcomes and retry only when nothing left the source | payments | Proposed | |
| [0041](0041-keep-identity-to-shielded-off-in-this-release.md) | Keep Identity to Shielded off in this release | payments | Proposed | |
| [0042](0042-report-moved-to-platform-when-a-shielded-to-identity-top-up-fails-after-the-unshield.md) | Report movedToPlatform when a Shielded to Identity top-up fails after the unshield | payments | Proposed | |

Areas: `spv`, `platform`, `keys`, `storage`, `coinjoin`, `payments`, `ui`, `build`, `process`. Each ADR takes one; a new
Area is added to this list in the PR that first needs it.

## Adding an ADR

- Take the next free number and name the file `NNNN-<decision-in-kebab-case>.md`; the title states
  the decision, not the problem.
- Start it as Proposed. It becomes Accepted only after a Reviewer who is not its author approves
  the PR that carries it.
- Follow the shape of ADR-0001: Status, Date and Deciders lines, then Context, Decision drivers,
  Considered options, Decision outcome, Consequences and Links. Considered options and
  Consequences are required. Decision outcome opens with one sentence, `**Chosen:** …`, that
  states the decision on its own.
- Add its row to the table above in the same PR, with one Area from the list under it.

Full rules: [ADR-0001, rules 3 and 5](0001-record-architecture-decisions-as-adrs.md).

## Superseding

An Accepted ADR is never edited, except for a redaction that the publicity rule requires (ADR-0001
rule 2). To change a decision, write a new ADR that names the old one. In the old ADR only the
status line changes, to `Superseded by ADR-NNNN`; in its row here, Status reads `Superseded` and
"Superseded by" links the new ADR. See
[ADR-0001, rule 3](0001-record-architecture-decisions-as-adrs.md).

## Number collisions

A number is never reused. If two open PRs take the same number, the author of the PR that merges
second renumbers its ADR to the next free number when rebasing and updates every reference to the
old number in that PR. See [ADR-0001, rule 3](0001-record-architecture-decisions-as-adrs.md).
