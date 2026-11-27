# 0074 — Judge request age by the wallet's clock and key expiry by block time

- **Status:** Proposed
- **Date:** 2026-11-24
- **Deciders:** PastaPastaPasta (ADR author)

## Context

ADR-0020 judged both a request's age and a key's expiry by the proved Platform block time. The
App Connect DIP (dashpay/dips#181) says the wallet refuses a request whose `CREATED_AT` is more
than 10 minutes behind the wallet's clock or more than 2 minutes ahead of it. On mainnet the
latest block is often minutes behind real time, so a request made just now was refused as dated
ahead of the network's time, the risk ADR-0020 listed under its negative consequences.

## Decision drivers

- Follow the DIP, which judges a request by the wallet's clock.
- A request scanned at once must be answered while the block time lags.
- Setting the phone's clock back must not keep a stale request alive.
- Platform stops an expired key by its own block time.
- The Android wallet and the 9.1.4 release judge a request by the device clock.

## Considered options

1. **The wallet's clock for a request's age, with the block time also making it stale; block time
   alone for a key's expiry.** A request is future when it is more than 2 minutes ahead of the
   wallet's clock, and stale when it is more than 10 minutes behind the wallet's clock or the block
   time, whichever is later.
2. **The wallet's clock alone for a request's age.** As Android does; a clock set back keeps a
   stale request alive.
3. **The later of the wallet's clock and the block time for both bounds.** A phone clock more than
   2 minutes slow then answers a request the DIP requires it to refuse.
4. **Block time alone, with a wider future bound** (ADR-0020's suggested widening). Still refuses
   a fresh request whenever the block time lags more than the bound, and departs from the DIP.

## Decision outcome

**Chosen:** option 1. A request's age follows the DIP's clock, and block time only ever makes a
request stale; a key's expiry stays on the clock Platform enforces.

## Consequences

**Positive**
- A request made just now is answered however far the latest block lags.
- A phone clock set back still cannot answer a request more than 10 minutes past the block time.

**Negative**
- A phone clock more than 2 minutes slow refuses requests as future, and one more than 10 minutes
  fast refuses them as stale, as the DIP requires. The future refusal names the device's clock.
- A request is still not judged without a proved block time.

**Neutral**
- Expiry, and everything else ADR-0020 decided about it, is unchanged.

## Links

- Supersedes: [ADR-0020](0020-judge-request-age-and-expiry-by-proved-platform-block-time.md)
- DIP: dashpay/dips#181 (`dip-pasta-app-connect.md`)
- Feature summary: [docs/features/app-connect/README.md](../features/app-connect/README.md)
