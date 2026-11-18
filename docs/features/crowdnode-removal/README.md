# CrowdNode removal

**Owner:** romchornyi · Introduced in [#1268](https://github.com/dashpay/dashwallet-ios/pull/1268)

## Why

The wallet no longer supports CrowdNode. Android removed its CrowdNode feature in dash-wallet #1664;
iOS still showed CrowdNode screens, validations and messages, and still searched the wallet's
history for CrowdNode transactions.
[ADR-0023](../../adr/0023-remove-crowdnode-entirely-as-android-does.md).

## What changed

- **No CrowdNode anywhere in the app**: no screens, Home shortcut, balance reminder, Explore item or
  banner, "emptying your wallet" warning, CrowdNode notifications or catalog strings. The app sends
  no CrowdNode requests. Past CrowdNode transactions stay in the history as ordinary rows.
- **The shortcut bar keeps its size and its buttons.** Saved shortcut values are pinned, the
  CrowdNode value is retired, and a saved CrowdNode slot gets the first action the bar doesn't show
  yet. [ADR-0024](../../adr/0024-pin-shortcut-raw-values-and-refill-the-retired-slot.md).
- **CrowdNode settings are deleted after the update**, for every wallet, by an exact list of the
  keys older builds wrote; the clean-up waits until the device has been unlocked. Removing a wallet
  or wiping the app deletes them too.
  [ADR-0025](../../adr/0025-remove-crowdnode-defaults-by-exact-key-list-on-activation.md).
- **Old CrowdNode notifications** leave the tray and no longer count in the badge; a tap on one
  just opens the app. [ADR-0026](../../adr/0026-retire-the-crowdnode-topic-by-marking-events-seen.md).

## What it guarantees

- After the update the app makes no CrowdNode network request and shows no CrowdNode text.
- Shortcut buttons other than CrowdNode keep their place and action.
- The clean-up deletes only CrowdNode settings and never records itself as done while the settings
  are unreadable.

## Not in scope

- Users who still hold a balance at CrowdNode cannot withdraw from the app; they withdraw on
  crowdnode.io. The app shows no message about it.
- crowdnode.io cookies and website data stay on the device, as on Android.
- Duplicate buttons that the existing availability fallbacks can produce on their own are a
  separate ticket.
