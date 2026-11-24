# Fresh shielded addresses on Receive

**Owner:** romchornyi · Introduced in the PR that adds this file · Issue
[#1372](https://github.com/dashpay/dashwallet-ios/issues/1372)

## Why

With Shielded selected, Receive always showed the wallet's default shielded address. Every payer
who saw it could tell that their payment went to the same wallet as everyone else's, which undoes
the privacy the Shielded pool is meant to give. The SDK could not hand out any other address, so
it gains two exports in dashpay/platform#5888.
[ADR-0046](../../adr/0046-build-fresh-shielded-addresses-across-the-app-and-swiftdashsdk.md).

## What changed

- **A new shielded address each time Receive gains focus**: opened from a tab, Home or the lock
  screen, back from the background, the Share sheet closed, switching back to Shielded, back from
  a pushed step, and on «Receive another». The SDK draws a random 88-bit diversifier index and
  never returns the default one; nothing is stored.
  [ADR-0047](../../adr/0047-draw-the-random-diversifier-index-inside-the-sdk.md).
- **The address holds while Receive keeps focus.** Sync, balance and pool updates never replace
  it, and Copy, Share and the QR code always carry the address on screen.
- **A placeholder until the address is ready**, with Copy and Share disabled. The default address
  is never shown first and then replaced.
- **A warned fallback.** If no fresh address can be produced, Receive shows the default address
  with a warning under the QR code that it is permanent and its payers can be linked. The next
  gain of focus tries again.
- **History reads transfers to own fresh addresses as own funds**, whether sent from this device
  or another, live or found by a restore scan.
  [ADR-0048](../../adr/0048-recognise-own-shielded-recipients-through-an-sdk-predicate.md).

The same applies on the Payments tab, the receive sheet of a Home balance row and lock-screen
Quick Receive.

## What it guarantees

- Two Receive sessions never show the same shielded address, except in the warned fallback.
- Every address ever shown stays payable, also after the app restarts, and a restore from the
  recovery phrase on iOS finds payments to all of them.
- No shown address shares anything with another beyond the network prefix, and none is the
  default address outside the fallback.
- Each address is encoded for the network the wallet is on at that moment.

## Not in scope

- The Shielded receipt fires for any new incoming shielded payment while Receive is open, not only
  for the address on screen.
- Android restore of fresh addresses is not verified here.
- On iOS 16+ the notification shade sends the app to the background, so Receive shows a new
  address after it.
- No on-screen note that older addresses still work.
