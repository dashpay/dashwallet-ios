# Receive to the identity

**Owner:** romchornyi · Jira MO-1123 · Android counterpart [dash-wallet#1677](https://github.com/dashpay/dash-wallet/pull/1677)

## Why

A Wallet holder could be paid to their identity by its ID, but the wallet never showed that ID
where a Payer is pointed to, and gave no feedback when credits landed.
[ADR-0033](../../adr/0033-model-receive-options-as-a-receive-only-enum.md),
[ADR-0034](../../adr/0034-subtract-own-top-ups-via-a-typed-top-up-event.md).

## What changed

- **A fourth Receive option, Identity**, with Advanced Mode on and a username on the Current
  identity, on both Receive presentations (Payments and the sheet from a balance row) and nowhere
  else. Receive options are a Receive-only enum; Send and Internal transfer keep their own type.
  [ADR-0033](../../adr/0033-model-receive-options-as-a-receive-only-enum.md).
- **The Identity card:** a QR of the bare Base58 Identity ID, the ID as text, the username, Copy,
  Share ID, Specify amount unavailable, and a warning that identity funds pay for Dash apps and
  usernames and that most exchanges and many wallets send only to Core.
- **A Receipt when credits arrive:** while the card is on screen and the app is in the foreground,
  the wallet reads the identity's credits every 5 s, starting from a fresh read made on opening.
  A rise shows a Receipt (amount in Dash and local currency, «Identity», «Received»).
- **No Receipt for the wallet's own top-ups:** every identity top-up announces the credits it
  supplied, and the starting balance moves up by them.
  [ADR-0034](../../adr/0034-subtract-own-top-ups-via-a-typed-top-up-event.md).

## Acceptance criteria

- **AC-01** The card shows a QR of the Identity ID, the ID as text (cut in the middle when it does
  not fit) and the username; Copy and Share are available, Specify amount is not.
- **AC-02** Copy copies exactly the ID or the username, with the usual copy confirmation.
- **AC-03** The QR and the shared text are exactly the Base58 Identity ID, nothing added.
- **AC-04** The card warns what identity funds are for and that many senders pay only to Core.
- **AC-05** A check that finds the credits higher than at opening shows a Receipt for the
  increase; payments between two checks give one Receipt for their sum.
- **AC-06** Credits that stay the same or go down raise no Receipt, and neither does a top-up of
  the identity from this wallet while Receive is open.
- **AC-07** After a Receipt, Identities and Internal transfer already show the new balance.
- **AC-08** Without Platform, the QR, ID, username, Copy and Share still work and the card does
  not say it is watching; credits that land during a gap after the starting balance was read show at
  the next successful check, while credits that land before the first successful read become part
  of the starting balance and raise no Receipt.
- **AC-09** With Advanced Mode off, Receive is unchanged and shows no Identity ID.
- **AC-10** Without an identity, a username, or with a registration in progress, there is no
  Identity option.
- **AC-11** Turning Advanced Mode off while on Identity moves Receive to Core.
- **AC-12** The option appears without leaving Receive once a username registration completes, or
  once the username is read after a cold start or a network switch.
- **AC-13** A wallet or network switch shows the new Current identity or removes the option;
  the previous identity's ID never shows and raises no Receipt.
- **AC-14** When the username is lost the option disappears; when it changes the card shows the
  new one.

## Known limits

Platform reports only the identity's balance, not transfers, so a Receipt reports a balance
increase:

- a top-up from another device with the same recovery phrase shows as «Received»;
- a fee and a payment between the same two checks show as their net;
- a lagging Platform node can lower the starting balance, so a later up-to-date read shows an
  earlier payment or an own top-up as «Received»;
- an own top-up that fails after Platform carried it out shows as «Received» (while an own
  top-up runs, no Receipt is raised);
- a Payer's credits that land between the last check and the end of an own top-up count as part
  of it up to the credits it supplied, so at most the top-up's fee worth of them raises no
  Receipt (they still show in the balance).

## Not in scope

- Specify amount on Identity.
- Paying to a scanned Identity ID from Send.
