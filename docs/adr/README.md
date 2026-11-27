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
| [0006](0006-choose-the-app-connect-login-by-the-protocol-version-read-at-runtime.md) | Choose the App Connect login by the protocol version read at runtime | platform | Superseded | [0053](0053-open-dashconnect-on-mainnet-and-gate-each-request-by-protocol-14.md) |
| [0007](0007-call-a-payment-links-sender-back-only-when-another-app-opened-the-link.md) | Call a payment link's sender back only when another app opened the link | payments | Proposed | |
| [0009](0009-answer-app-connect-request-v2-with-wallet-derived-keys-under-wallet-limits.md) | Answer App Connect request v2 with wallet-derived keys under wallet limits | platform | Proposed | |
| [0010](0010-probe-live-swap-routes-with-address-free-forced-quotes.md) | Probe live routes with address-free quotes forced to one provider | swap | Proposed | |
| [0011](0011-keep-live-swap-route-answers-in-one-shared-in-memory-store.md) | Keep live route answers in one shared in-memory store with two-step ageing | swap | Proposed | |
| [0012](0012-detect-a-near-outage-from-sentinel-coins.md) | Detect a NEAR outage from sentinel coins before per-coin checks | swap | Proposed | |
| [0013](0013-treat-dashuikit-and-swiftdashsdk-as-library-surfaces.md) | Treat DashUIKit and SwiftDashSDK as library surfaces of this feature | ui | Proposed | |
| [0014](0014-split-voting-state-into-a-shared-store-and-per-screen-view-models.md) | Split voting state into a shared store and per-screen view models | ui | Proposed | |
| [0015](0015-fence-a-pending-sign-in-on-disconnect.md) | Fence a pending sign-in on disconnect and recover forward only | platform | Accepted | |
| [0016](0016-turn-off-unrecorded-keys-on-disconnect-without-asking.md) | Turn off unrecorded keys on disconnect without asking | platform | Accepted | |
| [0017](0017-answer-an-app-connect-request-at-most-once.md) | Answer an App Connect request at most once | platform | Accepted | |
| [0018](0018-run-app-connect-platform-writes-through-one-executor.md) | Run App Connect Platform writes through one executor | platform | Accepted | |
| [0019](0019-let-one-state-table-decide-what-a-connection-shows-and-offers.md) | Let one state table decide what a connection shows and offers | platform | Accepted | |
| [0020](0020-judge-request-age-and-expiry-by-proved-platform-block-time.md) | Judge request age and expiry by proved Platform block time | platform | Superseded | [0079](0079-judge-request-age-by-the-wallets-clock-and-expiry-by-block-time.md) |
| [0021](0021-record-a-consensus-refusal-on-the-intent.md) | Record a consensus refusal on the intent and show it as Refused | platform | Accepted | |
| [0022](0022-derive-disconnected-apps-from-the-intents-a-disconnect-marked.md) | Derive disconnected apps from the intents a disconnect marked | platform | Accepted | |
| [0023](0023-remove-crowdnode-entirely-as-android-does.md) | Remove CrowdNode entirely, as Android does | ui | Proposed | |
| [0024](0024-pin-shortcut-raw-values-and-refill-the-retired-slot.md) | Pin shortcut raw values and refill the retired slot | ui | Proposed | |
| [0025](0025-remove-crowdnode-defaults-by-exact-key-list-on-activation.md) | Remove CrowdNode defaults by exact key list on activation | storage | Proposed | |
| [0026](0026-retire-the-crowdnode-topic-by-marking-events-seen.md) | Retire the CrowdNode topic by marking its events seen | storage | Proposed | |
| [0027](0027-derive-app-connect-connections-from-the-identity-and-recorded-intents.md) | Derive App Connect connections from the identity and recorded intents | platform | Accepted | |
| [0028](0028-answer-app-connect-v2-only-and-remove-the-two-scan-login.md) | Answer App Connect v2 only and remove the two-scan login | platform | Accepted | |
| [0029](0029-allow-a-new-app-connect-approval-while-another-is-confirming.md) | Allow a new App Connect approval while another one is still confirming | platform | Accepted | |
| [0030](0030-show-an-app-connect-connection-whose-response-was-not-published-as-not-delivered.md) | Show an App Connect connection whose response was not published as Not delivered | platform | Accepted | |
| [0031](0031-turn-off-unattributed-dashpay-profile-keys-with-any-disconnect.md) | Turn off unattributed DashPay profile keys with any disconnect | keys | Superseded | [0075](0075-turn-off-unattributed-dashpay-profile-keys-except-keys-that-cannot-be-checked.md) |
| [0032](0032-pass-owners-read-from-platform-into-the-pure-projection.md) | Pass the owners read from Platform into the pure App Connect projection | platform | Accepted | |
| [0033](0033-turn-off-only-the-unrecorded-keys-the-question-listed.md) | Turn off only the unrecorded keys the question listed | keys | Superseded | [0016](0016-turn-off-unrecorded-keys-on-disconnect-without-asking.md) |
| [0035](0035-run-every-vote-through-a-pure-vote-attempt-state-machine.md) | Run every vote through a pure vote-attempt state machine | ui | Proposed | |
| [0037](0037-cast-quick-voting-sequentially-under-one-authentication.md) | Cast Quick voting sequentially under one authentication | ui | Proposed | |
| [0038](0038-let-only-the-voting-store-write-the-remembered-node-choice.md) | Let only the voting store write the remembered node choice | ui | Proposed | |
| [0049](0049-record-the-publish-start-on-the-connection-intent.md) | Record the publish start on the connection intent | platform | Accepted | |
| [0050](0050-bound-an-unresolved-publish-by-48-hours-of-proved-platform-block-time.md) | Bound an unresolved publish by 48 hours of proved Platform block time | platform | Accepted | |
| [0052](0052-refuse-response-removed-at-its-one-write-point-while-the-publish-is-unresolved.md) | Refuse "response removed" at its one write point while the publish is unresolved | platform | Superseded | [0074](0074-report-a-kept-response-from-the-write-point-or-from-a-failed-lookup.md) |
| [0053](0053-open-dashconnect-on-mainnet-and-gate-each-request-by-protocol-14.md) | Open DashConnect on mainnet and gate each request by protocol 14 | platform | Accepted | |
| [0054](0054-keep-master-as-a-mirror-of-app-store-publications.md) | Keep master as a mirror of App Store publications | process | Accepted | |
| [0055](0055-keep-the-app-connect-rules-in-swift-until-android-shares-the-platform-wallet.md) | Keep the App Connect rules in Swift until Android shares the platform wallet | platform | Accepted | |
| [0056](0056-know-no-app-and-ask-before-returning-to-one.md) | Know no app: show every app as unknown and ask before returning to it | ui | Accepted | |
| [0057](0057-tell-a-connection-sheet-from-one-basis-and-placed-keys-only.md) | Tell a connection sheet from one basis, and claim access only from placed keys | ui | Accepted | |
| [0058](0058-answer-a-login-without-a-username-with-the-pages-own-state.md) | Answer a login without a username with the page's own state, and open nothing | ui | Accepted | |
| [0059](0059-route-every-app-log-line-through-dwlogger-with-an-os-logger-shaped-applogger.md) | Route every app log line through DWLogger with an os.Logger-shaped AppLogger | logging | Proposed | |
| [0060](0060-redact-log-values-at-interpolation-with-os-logger-privacy-defaults.md) | Redact log values at interpolation with os.Logger's privacy defaults | logging | Proposed | |
| [0061](0061-write-every-logged-error-as-a-type-case-and-code-summary.md) | Write every logged error as a type, case and code summary | logging | Proposed | |
| [0065](0065-recognize-platform-refusals-by-consensus-code-in-one-table.md) | Recognize Platform refusals by consensus code in one table | platform | Proposed | |
| [0066](0066-declare-the-app-and-the-zero-loss-check-as-the-feature-surfaces.md) | Declare the app and the zero-loss check as the feature's surfaces | l10n | Accepted | |
| [0067](0067-generate-the-catalog-from-the-baseline-lists-with-a-repository-script.md) | Generate the Catalog from the Baseline lists with a repository script | l10n | Accepted | |
| [0068](0068-rewrite-formatted-lookups-as-interpolations-and-move-their-entries.md) | Rewrite formatted lookups as interpolations and move their Catalog entries | l10n | Accepted | |
| [0069](0069-prove-zero-loss-by-pairing-each-code-place-with-its-baseline-key.md) | Prove zero loss by pairing each code place with its Baseline key | l10n | Accepted | |
| [0070](0070-keep-the-catalog-in-step-with-xcodes-own-string-sync-in-every-build.md) | Keep the Catalog in step with Xcode's own string sync in every build | l10n | Accepted | |
| [0071](0071-rewrite-swift-lookups-with-a-swiftsyntax-codemod-rerun-on-every-baseline.md) | Rewrite Swift lookups with a SwiftSyntax codemod re-run on every Baseline | l10n | Accepted | |
| [0072](0072-check-releases-through-the-key-map.md) | Check releases through the key map instead of pairing code places | l10n | Accepted | |
| [0073](0073-make-the-sync-phase-write-the-same-catalog-as-the-xcode-app.md) | Make the sync phase write the same Catalog as the Xcode app, and compile only the shipped locales | l10n | Accepted | |
| [0074](0074-report-a-kept-response-from-the-write-point-or-from-a-failed-lookup.md) | Report a kept response from the write point, or from the same predicate when the lookup fails | platform | Accepted | |
| [0075](0075-turn-off-unattributed-dashpay-profile-keys-except-keys-that-cannot-be-checked.md) | Turn off unattributed DashPay profile keys with any disconnect, except keys that cannot be checked | keys | Accepted | |
| [0079](0079-judge-request-age-by-the-wallets-clock-and-expiry-by-block-time.md) | Judge request age by the wallet's clock and key expiry by block time | platform | Proposed | |

Areas: `spv`, `platform`, `keys`, `storage`, `coinjoin`, `payments`, `swap`, `ui`, `l10n`, `build`, `process`, `logging`. Each ADR takes one; a new
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
