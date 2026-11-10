# 0026 — Retire the CrowdNode topic by marking its events seen

- **Status:** Proposed
- **Date:** 2026-11-05 (decision taken 2026-10-30 in review, recorded retroactively)
- **Deciders:** romchornyi (author)

## Context

Older builds posted CrowdNode notifications on the `crowdnode` thread (and earlier under the legacy id `CrowdNode`), and recorded them in `NotifiedEventStore`, a SQLite table that drives the unread badge and dedup. After the removal, these notifications can still sit in the tray, unseen rows still count in the badge, and a tap still carries the old `staking` route. A transaction notification can arrive in the background before the updated app is ever activated, and it recomputes the badge at that moment.

## Decision drivers

- Old notifications: a tap on an old CrowdNode notification opens the app normally and leads nowhere.
- Tray and badge: CrowdNode notifications leave the tray and the badge.
- Background badge: a background badge update before the first launch does not count CrowdNode events.
- The store's rows also serve dedup and must not be lost for other topics.

## Considered options

1. **Mark seen + clear the tray** — a one-time migration `MarkRetiredNotificationTopicsSeen` (version 20261030120000) marks unseen events of the retired `crowdnode` topic seen and keeps the rows. Every activation, `reconcileAfterBecomingActive` removes delivered notifications on the `crowdnode` thread and with the legacy `CrowdNode` id. An old tap decodes to no route.
2. **Delete the topic's rows** — a migration deletes every `crowdnode` row from `NotifiedEventStore`, and the tray is cleared the same way.
3. **Rely on activation only** — use the existing `markAllSeen()` on activation and the tray clean-up, with no migration.

## Decision outcome

**Chosen:** Option 1. Option 3 fails the background-badge driver, because a background notification before the first activation would count the CrowdNode events in the badge. Option 2 also meets the drivers, but it destroys rows that the store keeps for dedup and history, and it is harder to reason about than flipping a seen flag. The tray clean-up runs on every activation. Older builds scheduled the legacy `CrowdNode` and `Now` notifications with a one-second trigger, so one may still be pending at the update; activation cancels those pending requests too (`NotificationLifecycle.legacyPendingIdentifiers`). The current dispatcher posts with no trigger, so nothing else can be pending.

## Consequences

**Positive**
- The badge is correct from the first background update.
- The other topics' logic is untouched; the retired topic is data-only.

**Negative**
- `NotificationTopic.retiredRawValues` and `NotificationLifecycle.retiredIdentifiers` keep the `crowdnode` and `CrowdNode` strings forever, and they must not be reused.
- The migration can't be rolled back once it has run on a device.

**Neutral**
- The tray clean-up costs one notification-center query per activation.

## Links

- Pull request: [dashpay/dashwallet-ios#1268](https://github.com/dashpay/dashwallet-ios/pull/1268)
- Android counterpart: [dashpay/dash-wallet#1664](https://github.com/dashpay/dash-wallet/pull/1664)
- Related ADR: [0023 — Remove CrowdNode entirely, as Android does](0023-remove-crowdnode-entirely-as-android-does.md)
