# 0053 — Open DashConnect on mainnet and gate each request by protocol 14

- **Status:** Proposed
- **Date:** 2026-11-13
- **Deciders:** romchornyi (owner)

## Context

[ADR-0006](0006-choose-the-app-connect-login-by-the-protocol-version-read-at-runtime.md) kept DashConnect off on mainnet and left turning it on to a separate decision. Develop gates the whole feature by network: on mainnet the Connections page gets its mock data source and says "Available on test networks only", and the request parser refuses a request v2 for mainnet on both carriers ([ADR-0009](0009-answer-app-connect-request-v2-with-wallet-derived-keys-under-wallet-limits.md)).

Release 9.1.4 (18) was built from a release branch that dropped the network gate and relied on the protocol check alone, so DashConnect opened on mainnet when mainnet reached protocol 14. Mainnet now runs protocol 14, and develop is the source of the next release.

The App Connect DIP defines the `dash-key:` version 2 code for testnet and devnets only; on mainnet an app asks with a `dashpay://connect` link or code. Request intake already refuses a `dash-key:` code on mainnet with a reason that asks for a DashPay connect link (`AppConnect.intakeRefusal`).

## Decision drivers

- The next release from develop must not take DashConnect away from mainnet users of 9.1.4.
- What a network supports is read from the network (ADR-0006), not fixed in the build.
- Requests follow the DIP: on mainnet, `dashpay://connect` only.

## Considered options

1. **Open the page on every network; gate each request by the protocol version read at runtime.** Drop the network gate of the page and of the data source; keep the parser's mainnet refusal for `dash-key:` only.
2. **Keep DashConnect off on mainnet in develop.** The next release would turn it off for every 9.1.4 user on mainnet.
3. **Open mainnet by a build flag or a remote switch.** Adds a second gate beside the protocol check, with no case the protocol check does not already cover.

## Decision outcome

**Chosen:** option 1, because the protocol check already refuses every request on a network below 14, and mainnet is past it.

- `ConnectionsViewModel` treats the feature as available on every network; the real data source runs on mainnet.
- A v2 request on a network below protocol 14 is refused on the sheet (`AppConnect.isAvailable(protocolVersion:)`), as on testnet and devnets.
- The parser refuses a `dash-key:` version 2 code for mainnet and parses a `dashpay://connect` one for mainnet.
- This replaces the "Networks" rule of ADR-0009 and the "stays off on mainnet" note of ADR-0006.

## Consequences

**Positive**
- Develop and 9.1.4 behave alike on mainnet.
- A network that reaches protocol 14 needs no release to open DashConnect.

**Negative**
- An app that shows a `dash-key:` code on mainnet is refused, where 9.1.4 accepted it; the refusal asks for a DashPay connect link.

**Neutral**
- The Connections page's "Available on test networks only" state is left for previews and tests.
