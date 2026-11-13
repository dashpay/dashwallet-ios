# 0007 — Call a payment link's sender back only when another app opened the link

- **Status:** Proposed
- **Date:** 2026-11-09
- **Deciders:** llbartekll (author)

## Context

A payment link can carry `sender=<scheme>` (`dash:<address>?…&sender=<scheme>`, `dashwallet://pay=…&sender=<scheme>`). After the payment the wallet opens `<scheme>://callback=payack&address=…&txid=…`, so the app that asked for the payment learns it was made. For `dashwallet://pay=` links the confirmation also reads "Application <scheme> is requesting a payment to".

The wallet reads payment links from five sources: a link another app opens (a deep link), a QR code scanned inside the wallet, the pasteboard, an NFC tag, and an address typed or picked in the wallet. Before this decision every source that carried a `sender` called it back and, for `dashwallet://pay=`, named it (dashpay/dashwallet-ios#1219). The author of a QR code or a pasted link therefore chose which app the wallet opened after a payment and which name the confirmation showed.

## Decision drivers

- After a payment the user stays in the wallet unless an app on the same device sent them there.
- The confirmation names an app only when an app asked.
- Apps that hand the user to the wallet with a link keep the callback they rely on, in the same form.
- One rule that is easy to state and to test.

## Considered options

1. **Call back and name the sender only for a link another app opened.** A scan, a paste and an NFC tag carry no callback and no app label.
2. **Keep the callback for every source, with a validated scheme.** Nothing changes for callback consumers, but a printed code still decides where the user lands after paying.
3. **Ask before leaving the wallet** ("Return to <scheme>?") for sources other than a deep link. Keeps the scan-to-app flow, at the cost of a prompt whose only content is a name taken from the code.
4. **Remove the callback for every source.** Simplest, and breaks the apps that open the wallet with a link.

## Decision outcome

**Chosen:** option 1. The wallet calls a payment link's `sender` back, and names it on the confirmation, only when another app opened the link; a link the wallet read itself (scan, paste, NFC tag) names no app and calls none back.

In every case `sender` must be a bare custom URL scheme that neither the system nor the wallet answers; an invalid one is dropped and the payment still opens. The callback keeps its form.

A QR code read by the system Camera, or a link tapped in a browser, reaches the wallet as a deep link and cannot be told apart from a link an app opened. It keeps its callback, to a valid scheme only.

## Consequences

**Positive**
- A code or a pasted link no longer decides which app opens after a payment or which name the confirmation shows.
- Apps that open the wallet with a link are not affected.

**Negative**
- An app that showed a QR code for the user to scan inside the wallet and waited for the callback on the same device no longer gets it. It can open the wallet with the link instead.
- The system Camera and browser path keeps the old behaviour, so the rule depends on how the link reached the wallet, which the user does not see.

**Neutral**
- `ParsedPaymentURI` still carries the parsed `sender` for every source; `DWPaymentInput.callbackScheme` applies the rule.

## Links

- Issue: dashpay/dashwallet-ios#1219
- Related ADR: [0001 — Record architecture decisions as ADRs](0001-record-architecture-decisions-as-adrs.md)
