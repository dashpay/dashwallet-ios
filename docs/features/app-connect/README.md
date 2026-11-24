# DashConnect: sign in to an app with one QR

**Owner:** romchornyi · Introduced in [#1202](https://github.com/dashpay/dashwallet-ios/pull/1202); request v2 decoded in [#1204](https://github.com/dashpay/dashwallet-ios/pull/1204) and answered in [#1210](https://github.com/dashpay/dashwallet-ios/pull/1210); connections derived from the identity in [#1301](https://github.com/dashpay/dashwallet-ios/pull/1301)

## Why

Signing in to an app with DashConnect took two scans: one QR made the wallet publish a login key
to the app's own contract, and a second QR handed the wallet an identity update, built by the app,
that registered the app's keys. Platform protocol version 14 adds the App Connect system contract,
with the same id on every network, and lets the wallet register a bounded key itself. That makes a
one-scan login possible, and with it DashConnect on mainnet once mainnet runs protocol 14.

## What changed

- **One-QR login from protocol 14.** The wallet reads the network's protocol version before the
  approval sheet. From 14 it derives a session key for the request, registers it on the identity
  bound to the app's contract with a budget and an expiry, and publishes the encrypted key to the
  App Connect system contract. Below 14 App Connect is not offered.
  [ADR-0053](../../adr/0053-open-dashconnect-on-mainnet-and-gate-each-request-by-protocol-14.md).
- **App Connect v2 only** ([#1301](https://github.com/dashpay/dashwallet-ios/pull/1301)). The
  two-scan (v1) login is removed: a v1 `dash-key` QR is refused with a message asking the app for
  a new code. [ADR-0028](../../adr/0028-answer-app-connect-v2-only-and-remove-the-two-scan-login.md).
- **Connections come from the identity** ([#1301](https://github.com/dashpay/dashwallet-ios/pull/1301)).
  Before each identity update the wallet records an intent: the keys it is about to add or turn
  off, the app and the sealed response. The Connections rows are worked out from one read of the
  identity and these intents, not stored on their own. A connection is Active, **Confirming** (its
  update may still land) or **Not delivered** (its keys are live but its response was never
  published). [ADR-0027](../../adr/0027-derive-app-connect-connections-from-the-identity-and-recorded-intents.md),
  [ADR-0029](../../adr/0029-allow-a-new-app-connect-approval-while-another-is-confirming.md),
  [ADR-0030](../../adr/0030-show-an-app-connect-connection-whose-response-was-not-published-as-not-delivered.md).
- **The approval sheet shows what is approved**: what the session key can do, its budget and its
  lifetime. An unknown protocol version offers a retry, never an approval.
- **Disconnect is real**: it turns off the app's keys on the identity and deletes its responses;
  the row then shows Disconnected. An update of the app that may still land is closed off first:
  the wallet adds a key of its own at each id that update would take, then turns it off. Keys this
  wallet did not record giving (another device, a restore, an orphaned DashPay profile key) are
  turned off with it, without a question
  ([ADR-0016](../../adr/0016-turn-off-unrecorded-keys-on-disconnect-without-asking.md), which
  supersedes the confirmation in
  [ADR-0031](../../adr/0031-turn-off-unattributed-dashpay-profile-keys-with-any-disconnect.md)),
  and the result says how many there were. Keys it could not check, keys another app of the same
  owner may hold, and keys still live after a failed write are left on and named in the result; a
  failure keeps the row and Disconnect can run again.
- **DashConnect on mainnet.** The Connections page uses the real data source on every network. A
  request on a network below protocol 14 is refused; on mainnet a `dash-key:` v2 code is refused and
  a `dashpay://connect` request is answered
  ([ADR-0053](../../adr/0053-open-dashconnect-on-mainnet-and-gate-each-request-by-protocol-14.md)).
- **App Connect request v2** ([#1210](https://github.com/dashpay/dashwallet-ios/pull/1210)). A `v=2`
  code can name up to four auth bindings (a contract, a contract group or one document type) and
  two encryption bindings, each with the limits the app proposes. The wallet checks the request
  against Platform (who owns each contract, the identity hint), clamps the limits, derives one key
  per binding, and registers them in one identity update that also turns off the keys of its
  earlier grant on the same connection. The keys are published sealed on the App Connect contract,
  and for a request that came as a link the wallet asks `Return to <host>?` before it opens the
  app's callback ([ADR-0056](../../adr/0056-know-no-app-and-ask-before-returning-to-one.md)). A `dash-key:` v2 code for mainnet is refused; a
  `dashpay://connect` one is answered ([ADR-0053](../../adr/0053-open-dashconnect-on-mainnet-and-gate-each-request-by-protocol-14.md)).
  [ADR-0009](../../adr/0009-answer-app-connect-request-v2-with-wallet-derived-keys-under-wallet-limits.md).

- **Connection states and disconnect** ([#1334](https://github.com/dashpay/dashwallet-ios/pull/1334)).
  A connection is Active, Confirming, Not delivered, Refused, Expired or Disconnected, worked out
  from what Platform shows now and the wallet's record, and one state table decides what it shows
  and offers ([ADR-0019](../../adr/0019-let-one-state-table-decide-what-a-connection-shows-and-offers.md)).
  A request's age is judged by the wallet's clock, never earlier than Platform's proved block
  time, and a connection's expiry by the block time
  ([ADR-0074](../../adr/0074-judge-request-age-by-the-wallets-clock-and-expiry-by-block-time.md)); a
  request is answered at most once
  ([ADR-0017](../../adr/0017-answer-an-app-connect-request-at-most-once.md)). A disconnect turns
  off everything that may give the app access without a further question
  ([ADR-0016](../../adr/0016-turn-off-unrecorded-keys-on-disconnect-without-asking.md)), fences a
  sign-in that may still land
  ([ADR-0015](../../adr/0015-fence-a-pending-sign-in-on-disconnect.md)), and runs its writes
  through one executor ([ADR-0018](../../adr/0018-run-app-connect-platform-writes-through-one-executor.md)).
  A refusal by Platform is kept as Refused
  ([ADR-0021](../../adr/0021-record-a-consensus-refusal-on-the-intent.md)), and disconnected apps
  are derived from the intents a disconnect marked
  ([ADR-0022](../../adr/0022-derive-disconnected-apps-from-the-intents-a-disconnect-marked.md)).

- **A late response is not lost** ([#1374](https://github.com/dashpay/dashwallet-ios/issues/1374)).
  An approval stops waiting for the publish of the app's response at its timeout, but the publish
  keeps running. The intent records when the publish started
  ([ADR-0049](../../adr/0049-record-the-publish-start-on-the-connection-intent.md)); until the
  wallet knows its document, or it is 48 hours old in proved Platform block time
  ([ADR-0050](../../adr/0050-bound-an-unresolved-publish-by-48-hours-of-proved-platform-block-time.md)),
  no operation records the response removed
  ([ADR-0052](../../adr/0052-refuse-response-removed-at-its-one-write-point-while-the-publish-is-unresolved.md)).
  A publish Platform refused (a consensus rejection) leaves nothing to wait for; any other error
  keeps it unresolved. A submit that ends late is only logged; the next read decides.
  A disconnect in that window still turns the keys off at once and says the response may still
  appear; the Disconnected row shows "Response may still be on Platform". Opening Connections
  finds a late response without the PIN, and the next approval or disconnect on the identity
  deletes it.

## What it guarantees

- The app gets new keys that only it holds, each bound to the contract, group or document type the
  user approved, with an expiry and the budget the sheet showed. It never gets the identity's
  existing keys or the recovery phrase.
- Approving the same QR again registers no second key.
- The wallet records a key before it submits the key's registration, so a key that lands without
  a confirmation is still found and can be turned off.

## Later changes

- **The redesigned Connections page and approve sheet**
  ([#1277](https://github.com/dashpay/dashwallet-ios/pull/1277),
  [#1399](https://github.com/dashpay/dashwallet-ios/pull/1399),
  [#1289](https://github.com/dashpay/dashwallet-ios/pull/1289),
  [#1293](https://github.com/dashpay/dashwallet-ios/pull/1293),
  [#1278](https://github.com/dashpay/dashwallet-ios/pull/1278)). Active, Disconnected and Expired
  tabs on the state table above; a connection sheet whose access and funding come from one read of
  the identity, with access claimed only from keys whose bound is known
  ([ADR-0057](../../adr/0057-tell-a-connection-sheet-from-one-basis-and-placed-keys-only.md)); an
  approve sheet with funding limit and expiry pickers that shows every app as unknown and asks
  before returning to it
  ([ADR-0056](../../adr/0056-know-no-app-and-ask-before-returning-to-one.md)). A login request on
  a wallet without a username opens nothing; the page asks for a username
  ([ADR-0058](../../adr/0058-answer-a-login-without-a-username-with-the-pages-own-state.md)). The
  rules stay in Swift for now
  ([ADR-0055](../../adr/0055-keep-the-app-connect-rules-in-swift-until-android-shares-the-platform-wallet.md)).

- **Encryption keys and the `dashpay://connect` carrier**
  ([#1258](https://github.com/dashpay/dashwallet-ios/pull/1258),
  [#1257](https://github.com/dashpay/dashwallet-ios/pull/1257)). Encryption keys are chosen by the
  DIP's rotation rules
  ([ADR-0009](../../adr/0009-answer-app-connect-request-v2-with-wallet-derived-keys-under-wallet-limits.md)),
  and on mainnet a request arrives as a `dashpay://connect` link
  ([ADR-0053](../../adr/0053-open-dashconnect-on-mainnet-and-gate-each-request-by-protocol-14.md)).

## Not in scope

- The approval boundary as one place (a request re-checked after the PIN against Platform) is
  [#1273](https://github.com/dashpay/dashwallet-ios/issues/1273).

The screens follow the design canon in [`docs/design-system.md`](../../design-system.md).
