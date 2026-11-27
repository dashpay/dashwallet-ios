# 0078 — Hold a login while the username is unknown, and answer it once the names are read

- **Status:** Proposed
- **Date:** 2026-11-27 (#1535)
- **Deciders:** romchornyi (ADR author)
- Supersedes [ADR-0058](0058-answer-a-login-without-a-username-with-the-pages-own-state.md).

## Context

ADR-0058 drops a login request before it is parsed when the wallet has no username, and also when
the username is not read yet (`usernameUnknown`): the page says "The wallet is still reading your
username. Try again in a moment." and the app has to ask again.

A login link usually opens the wallet from a cold start (#1434). At that moment the SDK is not
running, so the identity snapshot is still loading; after a restore or a reinstall the identity
row appears only when identity recovery finishes. Both read as "not known yet", and the user had
to go back to the app and start the sign-in over on nearly every cold start. Worse, a loading
snapshot read as "no identity" and showed "Create username" to a wallet that has one.

## Decision drivers

- A cold start from a login link reaches the approve sheet without the user starting over.
- Never ask a user to create a username they may already have.
- Read nothing from the network for a request the wallet will not answer (ADR-0058, kept).
- Never open a return the user did not see a sheet for (ADR-0056, kept).

## Considered options

1. **Keep ADR-0058**: refuse while unknown; the app asks again.
2. **Hold while unknown**: keep the one latest request, unparsed, until the names are read, then
   take it through the normal path; refuse as ADR-0058 when the names show no username or are not
   read in time.

## Decision outcome

**Chosen:** hold while unknown.

- **Unknown, not missing:** the username state is unknown while the identity snapshot loads, while
  identity recovery for the wallet on its network has not settled, or while an identity's names
  are not read. It is missing only when recovery proved there is no identity, or the names were
  read and none is the wallet's. Recovery that found an identity but stopped before the store
  confirmed its row (the retry cap) leaves the state unknown. An empty scan is no proof of absence
  while the SDK wallet manages an identity (its discovery reports only identities it did not
  manage): that identity is acted on as found.
- **What waits:** one login request that reads as a request for the wallet's network (the local
  parse, nothing from the network); one that does not read is refused at once. It waits only when nothing else on the page owns
  the answer: no approve, purchase or return sheet, no connection sheet up or going, no signing,
  resolving or disconnect under way. Otherwise ADR-0058's answer applies at once. A `dash-st:`
  request never waits (unchanged).
- **Replacement:** a newer request replaces the held one; the held one is dropped without an answer.
- **Wake-up:** the SDK runtime start, identity recovery settling, and the registration update read
  the state again. Holding a request starts the names' read again when an earlier one failed;
  without an identity row it runs identity recovery again when its last run on this runtime
  ended without an answer (Platform was down), at most twice per wallet and network, without
  restarting Core. Only a request that reads may start a read or a recovery run. A recovery run
  that replaces another starts only once that one returned, so a stop waits for every run.
- **Scope:** the held request goes on only under the wallet and chain it came to (on devnet the
  chain includes the configured devnet name; recovery's answers are kept per chain too); after a
  switch it is dropped without an answer. A request held before any wallet was open (a first
  launch that keeps the wallets) belongs to the first wallet that opens on that network.
- **Timeout:** after 30 seconds still unknown, it is refused with ADR-0058's "still reading" note,
  and the app has to ask again.
- **Missing:** once the state reads missing, the held request is refused exactly as ADR-0058
  says for a wallet without a username.
- **Surviving the tab rebuild:** the DashPay tabs that appear once the name is read, and an
  active-wallet change that is no switch (the same wallet starting again, the first wallet
  opening), keep the More tab's navigation and the Connections page on it.

## Consequences

**Positive**
- A cold-start login, including one right after a restore, reaches the approve sheet once the
  names are read.
- A wallet that owns a username is no longer asked to create one while its identity loads.
- Still nothing is read from the network for the request until the username is known.

**Negative**
- The page waits up to 30 seconds with a progress overlay before a refusal.
- A request stays in memory while held; it is kept as given and parsed again when taken.
- The request itself still names only `devnet`, so a request made for another devnet with the
  same seed is not told apart; the held one is dropped when the configured devnet changes.
- On a wallet without an identity the create-username page shows only after recovery settles; a
  failed recovery keeps the state unknown for the rest of the start, past the two asked retries.
- A wallet whose found identity the store never confirmed gets "still reading" on every login
  until the next start, not a create-username prompt.

**Neutral**
- A no-username wallet and a token purchase keep ADR-0058's answers.

## Links

- Code: `ConnectionsViewModel.receive`, `holdUntilTheUsernameIsRead`, `refreshUsername`,
  `DashConnectHostingController.usernameState`, `DWSameSeedIdentityRecoveryCoordinator.isSettled`,
  `IdentityRecoveryLedger`, `PlatformAddressSyncCoordinator.retryIdentityRecovery`,
  `MainTabbarController.moreNavigation`, `MainTabbarController.isTheSameWallet`
- Supersedes [ADR-0058](0058-answer-a-login-without-a-username-with-the-pages-own-state.md)
- Related ADR: [ADR-0056](0056-know-no-app-and-ask-before-returning-to-one.md)
- Issue: [#1434](https://github.com/dashpay/dashwallet-ios/issues/1434)
