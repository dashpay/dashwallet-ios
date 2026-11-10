# 0023 — Remove CrowdNode entirely, as Android does

- **Status:** Proposed
- **Date:** 2026-11-05 (decision taken 2026-10-30, recorded retroactively)
- **Deciders:** romchornyi (author)

## Context

Jira MO-1115 asks to remove CrowdNode from the iOS app: no screens, validations or messaging, and no search for CrowdNode transactions. When the work started, Android shipped CrowdNode in a withdraw-only mode with a "withdraw your funds" message (dash-wallet #1490, #1497). On 2026-11-03 Android merged its own full removal (dash-wallet #1664, MO-1114): the module, the Staking entry and shortcut, the leftover-balance check and CrowdNode history grouping are gone. The iOS feature had to decide whether to keep a withdraw path for depositors.

## Decision drivers

- Goals: no Wallet holder meets CrowdNode anywhere; the app does no CrowdNode work.
- Consistency with Android, which removed CrowdNode in dash-wallet #1664.
- Complete removal: 0 CrowdNode requests, 0 CrowdNode strings.

## Considered options

1. **Remove entirely** — delete every CrowdNode screen, entry point, check, notification, string and API call; depositors withdraw on crowdnode.io.
2. **Withdraw-only mode** — keep the account and withdraw screens plus a "withdraw your funds" banner, as Android did before #1664.

## Decision outcome

**Chosen:** Option 1. It meets both goals outright, matches Android's #1664, and removes the CrowdNode API client and its launch and Home requests. Option 2 keeps a CrowdNode client and screens alive for a service the wallet no longer supports.

## Consequences

**Positive**
- About 70 Swift files, the storyboard, assets and 132 catalog keys in 43 locales are gone, and no CrowdNode request leaves the app.
- iOS and Android behave the same for CrowdNode depositors.

**Negative**
- A depositor with a balance at CrowdNode cannot withdraw from the app and has to use crowdnode.io.
- Upgrade code has to handle what older builds left behind (ADR-0024, ADR-0025, ADR-0026).

**Neutral**
- Bringing a CrowdNode feature back would mean rebuilding it from git history; nothing in the current code depends on it.

## Links

- Pull request: [dashpay/dashwallet-ios#1268](https://github.com/dashpay/dashwallet-ios/pull/1268)
- Android counterpart: [dashpay/dash-wallet#1664](https://github.com/dashpay/dash-wallet/pull/1664)
- Related ADR: [0024 — Pin shortcut raw values and refill the retired slot](0024-pin-shortcut-raw-values-and-refill-the-retired-slot.md)
- Related ADR: [0025 — Remove CrowdNode defaults by exact key list on activation](0025-remove-crowdnode-defaults-by-exact-key-list-on-activation.md)
- Related ADR: [0026 — Retire the CrowdNode topic by marking its events seen](0026-retire-the-crowdnode-topic-by-marking-events-seen.md)
