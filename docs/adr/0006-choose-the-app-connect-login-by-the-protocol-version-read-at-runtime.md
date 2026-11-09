# 0006 — Choose the App Connect login by the protocol version read at runtime

- **Status:** Proposed
- **Date:** 2026-11-06
- **Deciders:** romchornyi (author)

## Context

Before this decision, signing in to an app with DashConnect took two scans. The first QR (`dash-key:`) made the wallet publish an encrypted login key to the app's own key-exchange contract. The second (`dash-st:`) handed the wallet an identity update, built by the app, that registered the app's keys.

Platform protocol version 14 adds the App Connect system contract (dashpay/platform#4869). It has the same id on every network, so the wallet can publish its answer there without a per-network contract. Protocol 14 also lets the wallet itself register a key bound to one contract, with a budget and an expiry. Networks run different protocol versions: devnets and testnet already run 14, mainnet does not yet. The wallet ships one build for all of them.

## Decision drivers

- One build serves every network. The network's own protocol version decides which login runs, not the build.
- The user approves, on one sheet, exactly the key the wallet will register: what it can do, its budget and its lifetime.
- An unknown protocol version is shown as unknown, never guessed (repository guardrail 3).
- Networks below protocol 14 keep the two-scan login they have.

## Considered options

1. **Read the protocol version at runtime and pick the login from it.** From 14 the wallet derives a session key, registers it on the identity bound to the app's contract with a budget and an expiry, and publishes the encrypted key to the App Connect system contract. Below 14 the two-scan login runs unchanged.
2. **Pin each network's protocol version in the build.** Simple, but every network upgrade needs a release, and a pin that runs ahead of or behind the network sends the wrong login.
3. **Replace the two-scan login with the one-QR login on every network now.** Networks below 14 would lose the login, because the system contract does not exist there.

## Decision outcome

**Chosen:** option 1. The wallet reads the protocol version from the current epoch before it shows the approval sheet. From protocol 14 it runs the one-QR login, below 14 the two-scan login. When the version cannot be read, the sheet offers a retry and nothing to approve. The approval is refused, and the sheet rebuilt, when the network's login is no longer the one the sheet showed.

DashConnect stays off on mainnet in this change: the Connections page uses its mock data source there. Turning it on for mainnet is a separate decision.

## Consequences

**Positive**
- A network gets the one-QR login when it reaches protocol 14, with no release.
- The session key the wallet registers is bound to one contract and limited by budget and expiry, so the app never holds an identity key or the recovery phrase.
- The answer goes to one system contract with the same id on every network, so no per-network contract id is needed.

**Negative**
- Every approval waits for a proved epoch read.
- An app that still shows a v1 `dash-key:` code on a protocol-14 network gets a key registered and an Active row, but its response goes to the App Connect contract, which that app does not read, so its sign-in does not complete.
- While networks below 14 exist, the wallet keeps both logins and their code.

**Neutral**
- The budget (0.05 DASH) and lifetime (90 days) are placeholders in this change (`TODO(app-connect-limits)`).

## Links

- Feature summary: [docs/features/app-connect/README.md](../features/app-connect/README.md)
- Related ADR: [0001 — Record architecture decisions as ADRs](0001-record-architecture-decisions-as-adrs.md)
