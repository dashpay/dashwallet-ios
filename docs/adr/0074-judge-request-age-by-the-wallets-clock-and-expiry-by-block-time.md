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

1. **The later of the wallet's clock and the proved block time for a request's age; block time
   alone for a key's expiry.** Block time can mark a request stale but never future.
2. **The wallet's clock alone for a request's age.** As the DIP and Android do; a clock set back
   keeps a stale request alive.
3. **Block time alone, with a wider future bound** (ADR-0020's suggested widening). Still refuses
   a fresh request whenever the block time lags more than the bound, and departs from the DIP.

## Decision outcome

**Chosen:** option 1. A request's age follows the DIP's clock, never judged earlier than the
block time; a key's expiry stays on the clock Platform enforces.

## Consequences

**Positive**
- A request made just now is answered however far the latest block lags.
- A phone clock set back still cannot answer a request more than 10 minutes past the block time.

**Negative**
- A phone clock more than 10 minutes fast refuses requests as stale, as the DIP requires.
- While the phone's clock is behind the block time, the 2-minute "future" bound is judged against
  the block time, which is looser than the DIP: a request more than 2 minutes ahead of a slow
  phone clock but within 2 minutes of the block time is answered.
- A request is still not judged without a proved block time.

**Neutral**
- Expiry, and everything else ADR-0020 decided about it, is unchanged.

## Links

- Supersedes: [ADR-0020](0020-judge-request-age-and-expiry-by-proved-platform-block-time.md)
- DIP: dashpay/dips#181 (`dip-pasta-app-connect.md`)
- Feature summary: [docs/features/app-connect/README.md](../features/app-connect/README.md)
