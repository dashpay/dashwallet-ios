# Say where the money went after a failed Shielded username registration

**Owner:** romchornyi · Fixes [#1265](https://github.com/dashpay/dashwallet-ios/issues/1265); builds on [#1267](https://github.com/dashpay/dashwallet-ios/pull/1267)

## Why

A username registration paid from Shielded creates the identity with one Type-20 transition. When
the network rejects it in a block, the exit has already left the shared pool: the network keeps a
penalty and sends the rest (about 0.0298 DASH for a 0.03 standard exit) to the wallet's lowest
Platform Payment address. Until now the wallet showed the SDK's raw error, never said that the
money came back or where, and a retry from Platform Payment failed because 0.0298 is below the
0.032 a standard name needs from there. The money was safe but looked lost.

## What changed

- **A charged failure is recognised.** The failure of the Type-20 call is classified as charged,
  unknown outcome or other. Charged means the platform wallet SDK proved, at the node the create
  went to, that its inputs are spent and its identity was not created
  ([dashpay/platform#5853](https://github.com/dashpay/platform/pull/5853)). A node's rejection
  text is never trusted. [ADR-0035](../../adr/0035-classify-a-charged-shielded-registration-failure-by-the-sdks-proven-outcome.md).
- **A failure proven later is explained too.** When the SDK cannot read the outcome during the
  call (connection lost after the create was sent), the attempt is kept, amount-free. Once a later
  sync proves its inputs consumed (the create's activity row gets the SDK's `InputsConsumed`
  status), the row explains the charged failure, after a relaunch too.
- **The registration's row explains it.** On Home and More the row says "The registration did not
  go through." and "Checking where the money went…" until Platform address sync sees the funds.
  Then it states the returned amount, names the Platform balance as where it went, and says how
  much to add there to try again, or that the name can be registered from it now. A contested name
  gets its own figures (0.25 exit), and no word about a contest fee.
- **The returned amount is what arrived.** It is the first synced increase of the fallback address
  over a snapshot taken just before the transition was sent, rounded down to the duff; once stated
  it never changes. The amount to add follows the Platform Payment balance as it is now.
  [ADR-0036](../../adr/0036-measure-returned-funds-as-the-fallback-address-increase.md).
- **The explanation survives a restart.** A small failure record in the app's defaults, scoped to
  one wallet on one network, keeps it until the next registration in that wallet starts or one
  succeeds. A second charged failure replaces it, never adds to it. Deleting a wallet removes only
  that wallet's record.
- **No raw technical text** for a Shielded-paid registration: a failure the wallet cannot classify
  reads "The registration did not go through.", and the name step's known causes (name taken, vote
  started, request limit, already requested, clock skew) get their own plain sentences. The SDK
  text goes to the log only. Dash and Platform Payment registrations keep today's wording.

## What it guarantees

- The wallet says money came back only after the network has decided the registration failed. An
  unknown outcome keeps the existing "still confirming" handling, with no amount.
- The stated amount equals the rise of the Platform Payment balance when nothing else moved it.
- One wallet's figures never show in another wallet or on the other network.

## Not in scope

- Letting a retry pay from the returned funds alone: the Platform Payment funding rule is unchanged.
- A button or preselected source on the failure: the explanation is text only.
- Returning the money to Shielded instead of Platform Payment.

## Operational notes

- No migration, no feature flag. The failure record is a new key in the app's defaults.
- Needs a platform pin with dashpay/platform#5853; until it merges, `.platform-ref` points at that
  PR's head and moves to the merged commit before this PR merges.
- Rollback: revert the PR; a left-over record key is ignored by builds without this change.
