# 0025 — Remove CrowdNode defaults by exact key list on activation

- **Status:** Proposed
- **Date:** 2026-11-05 (decision taken 2026-10-30, refined in review on 2026-10-30, recorded retroactively)
- **Deciders:** romchornyi (author)

## Context

Older builds stored CrowdNode's settings in `UserDefaults.standard`: account state, account address, email, signed message id, fee and similar. Some are global, some bare legacy keys, and some per wallet as `<key>_<walletIdHex>`, for every wallet on the device. One key name starts with a Cyrillic "с" (U+0441), and three have generic names. Before the first unlock after a reboot, protected data is unavailable and the defaults read back empty. A wallet wipe used to call CrowdNode's own reset, which no longer exists.

## Decision drivers

- Every wallet: CrowdNode data of every wallet is deleted; after success, later launches do nothing more.
- No over-deletion: the clean-up never touches data outside CrowdNode data.
- Locked device: nothing is recorded as done while the data is unreadable.
- Wipe: a wipe leaves no CrowdNode data behind.
- Parity with Android's clean-up of the named CrowdNode keys (dash-wallet #1664).

## Considered options

1. **Exact key list, on activation, until done** — `RetiredCrowdNodeDefaults` holds the 17 key names copied byte for byte and removes each bare key plus every per-wallet copy `<key>_<wallet id>`, where the suffix must be a non-empty lowercase-hex wallet id as the old code wrote it (`%02x` per byte); a key with any other suffix is kept. It is called from `handleDidBecomeActive`, skips an activation without protected data, and sets a done flag in `UserDefaults.standard` after it ran. The wallet wiper calls the same type.
2. **Prefix match on "crowdNode"** — remove every key whose name starts with the CrowdNode prefix.
3. **Once at launch, unconditionally** — run from `didFinishLaunching` and set the done flag right away.
4. **No clean-up** — leave the data on the device unused.

## Decision outcome

**Chosen:** Option 1. Option 2 misses the Cyrillic key and the three generic names, and could catch a foreign key that happens to share the prefix. Option 3 can run in the background before the first unlock, read empty defaults and record the work as done without deleting anything. Option 4 leaves confidential data (an account address and an email) on the device, against the goal of deleting CrowdNode data and against Android's behaviour. The done flag lives in `UserDefaults.standard` rather than `DWGlobalOptions`, because a wipe clears `DWGlobalOptions`.

## Consequences

**Positive**
- Exactly CrowdNode's data is removed, for every wallet, and `RetiredCrowdNodeDefaultsTests` proves it for each key form.
- A locked-phone launch can't mark the clean-up done early.

**Negative**
- The key list is a frozen copy of the old code; a key it misses stays on the device.
- The generic key names become reserved, because the wiper removes them on every wipe.

**Neutral**
- The done flag and the type stay in the app indefinitely; removing them later only needs a release that is old enough.

## Links

- Pull request: [dashpay/dashwallet-ios#1268](https://github.com/dashpay/dashwallet-ios/pull/1268)
- Android counterpart: [dashpay/dash-wallet#1664](https://github.com/dashpay/dash-wallet/pull/1664)
- Related ADR: [0023 — Remove CrowdNode entirely, as Android does](0023-remove-crowdnode-entirely-as-android-does.md)
