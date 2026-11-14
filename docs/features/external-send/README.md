# Send to an address

**Owner:** romchornyi · Jira MO-1121 · Android counterpart [dash-wallet#1680](https://github.com/dashpay/dash-wallet/pull/1680)

## Why

The Send flow that pays someone outside the wallet predated the new Payments design and paid only
from Core, Shielded and Platform to Core, Shielded and Platform addresses. Identity credits could
not be spent from Send, and nobody could pay to an Identity ID. The new design (Address → Send →
Confirm → Sending, with a Select source sheet) and Android's MO-1121 bring every balance and every
destination type into one flow.

## What changed

- **One flow for every entry point:** the Send menu's address row, Scan Dash QR, the scan button in
  the address field, a balance row's Send (that balance pinned as the source) and a dash: link
  opened by another app or the browser. The username row opens the existing send-to-username flow.
- **Four sources, four destination types.** Core, Shielded, Platform and the Current identity pay
  to a Core address (or a dash: payment request), a Platform address, a Shielded address or an
  Identity ID. The type is judged by the whole address, not its prefix. Every source and
  destination pair is decided in one pure policy; a pair that cannot pay stays visible in Select
  source with its reason. [ADR-0038](../../adr/0038-decide-every-source-and-destination-pair-in-one-policy.md).
- **A new module over the existing spend paths:** a ViewModel per screen and one executor that
  calls the wallet's existing send, transfer, withdrawal, shield/unshield and identity seams. No
  new way of spending money.
  [ADR-0037](../../adr/0037-build-external-send-as-a-new-module-over-the-existing-spend-seams.md).
- **Fee on Send, binding fee on Confirm:** Send shows an estimate; Continue authenticates and
  prepares the send, Confirm shows the prepared fee and total, and its tap only broadcasts. A fee
  that no longer fits sends the holder back to Send.
  [ADR-0039](../../adr/0039-estimate-the-fee-on-send-and-recompute-it-on-confirm.md).
- **Three outcomes:** sent; not sent (nothing left the source, Retry returns to Send with the same
  destination, source and amount); in progress (any doubt, no Retry, the sheet closes with a
  "Send in progress" Toast and the existing recovery finishes it).
  [ADR-0040](../../adr/0040-report-three-send-outcomes-and-retry-only-when-nothing-left-the-source.md).
  A Shielded → Identity top-up that fails after the unshield says the money moved to the Platform
  balance. [ADR-0042](../../adr/0042-report-moved-to-platform-when-a-shielded-to-identity-top-up-fails-after-the-unshield.md).
- **Identity → Shielded stays off** in this release, with its reason, even once the SDK binding
  for it is available: its fee is only known after the payment runs.
  [ADR-0041](../../adr/0041-keep-identity-to-shielded-off-in-this-release.md). The binding itself
  is the feature's second surface, in dashpay/platform.
  [ADR-0036](../../adr/0036-ship-the-ios-screens-and-the-sdk-binding-as-two-surfaces.md).
- **Max** fills the source balance minus the fee on every route; on Identity it also keeps the
  DashPay reserve (the low-credit threshold), so contact requests and profile updates keep working.
- **Callbacks:** a dash: link's `sender` is called back after a payment request only when another
  app opened the link ([ADR-0007](../../adr/0007-call-a-payment-links-sender-back-only-when-another-app-opened-the-link.md)).

## Pairs

| Source ↓ / Destination → | Core address | Platform address | Shielded address | Identity ID |
|---|---|---|---|---|
| Core | send (a payment request: Core only) | asset lock; script form unavailable | shield | own Current identity: top-up; others unavailable |
| Shielded | unshield to Core (withdrawal) | unshield | shielded transfer | top-up through Platform |
| Platform | withdrawal | transfer; script form unavailable | shield | top-up |
| Identity | withdrawal | credit transfer | unavailable (ADR-0041) | credit transfer; own Current identity unavailable |

## Acceptance criteria

- **AC-01** A valid Core address and an amount reach Confirm with From, To, network fee and total;
  after Confirm the send shows in progress.
- **AC-01b** When the fee cannot be worked out, Confirm is blocked with a retry, for every source.
- **AC-02** An address that fails its format check or belongs to another network cannot continue.
- **AC-03** The clipboard is read only after the holder taps to show it.
- **AC-04** Platform and Shielded addresses (same prefix) are told apart by the whole address.
- **AC-05** Select source lists every source by its icon and name, without balances; picking one
  updates Send.
- **AC-06** An unavailable pair shows in Select source with its reason and cannot be picked.
- **AC-07** Without a Current identity with a username, Identity is not offered.
- **AC-08** Max is the balance minus the fee; a larger amount cannot continue and says the balance
  is not enough.
- **AC-09** Max on Identity keeps the DashPay reserve and explains it; a typed amount below the
  reserve is allowed with a warning on Send and Confirm; with nothing above the reserve Max is
  disabled with a note.
- **AC-10** The starting source is the first one with a balance that can pay the destination,
  never Identity.
- **AC-11** DASH and the local currency convert both ways; the send uses the DASH amount.
- **AC-12** Someone else's Identity ID shows the identity (and username) and says the money goes
  to that identity's balance.
- **AC-12b** The holder's own Current identity is a top-up of their credits.
- **AC-13 / AC-13b** An Identity ID that does not exist cannot continue; one that cannot be
  checked says so (not "not found") and offers a retry.
- **AC-14** A balance row's Send pins that source; a pinned source that cannot pay is replaced and
  Send says so.
- **AC-15** A scan detects every destination type; a dash: link with a Core, Platform or Shielded
  address or an Identity ID fills that destination and its amount, scanned, pasted or opened from
  another app alike, and a payment request's amount cannot be changed.
- **AC-16** From Shielded, Platform or Identity to Core, Confirm says it is a withdrawal that
  arrives after a delay.
- **AC-17** From Shielded to anything but Shielded, Confirm warns that the amount and destination
  become public.
- **AC-18** The warnings the old Send showed (wrong address, processing time, full withdrawal,
  emptying Core) still show on Confirm.
- **AC-19** A send that fails before money left the source says why, and Retry returns to Send.
- **AC-20** The username row opens the send-to-username flow as before.

## Screens

Code comments name the screens by these ids.

| Id | Screen | Id | Screen |
|---|---|---|---|
| SCR-01 | Send menu | SCR-07 | Spend authentication (existing) |
| SCR-02 | Address | SCR-08 | Sending |
| SCR-03 | QR scanner (existing) | SCR-09 | Result (existing success views, in-progress Toast) |
| SCR-04 | Send | SCR-10 | Send failed |
| SCR-05 | Select source | SCR-11 | Balance row (existing) |
| SCR-06 | Confirm | SCR-12 | Send to username (existing) |

## Known limits

- **Core → Platform address after an interruption:** the app keeps its own note of who an
  asset lock pays. If that note is missing or unreadable, recovery refuses to finish the payment
  rather than guess, and the Dash stays in the lock ("the wallet can't confirm who it should
  pay"). A wipe or a restore drops the notes, so a lock left unfinished at that moment stays
  locked, the holder's own transfers included. The SDK will store the recipient with the lock
  before broadcast: [dashpay/platform#5824](https://github.com/dashpay/platform/issues/5824).
- No progress view while a Core payment locks, and no pending or failed sends in History; deferred
  like on Android.
- The old Send screen stays: send to a username and the older Payments screens still use it.

## Not in scope

- The send-to-username flow beyond its menu row.
- Advanced Mode gating: iOS shows every source the holder has.

## Test coverage

Unit and component tests cover the pair policy, the parser, every screen's ViewModel, the flow and
the executor over fakes. The Live adapters are tested up to the SDK edge only: building, signing
and broadcasting need a funded wallet and the network, which the unit-test host does not have.
Those paths are checked by hand on a funded testnet wallet.
