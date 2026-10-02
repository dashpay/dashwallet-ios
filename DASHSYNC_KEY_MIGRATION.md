# DashSync -> SwiftDashSDK key migration

Current contract for importing wallet mnemonics from DashSync-owned keychain
entries into the host-owned SwiftDashSDK runtime. Updated 2026-07-11 to include
multi-wallet and active-wallet behavior, and 2026-09-30 for mnemonics orphaned
by a DashSync Reset.

## Deployment model and invariant

The migrator ships in the same release as the final DashSync removal. Normal
migration treats old DashSync state as read-only. Explicit production
`Wallets -> Remove`, recovery wipe, and confirmed `Delete All` may delete only
the affected `WALLET_MNEMONIC_KEY_*` accounts from the DashSync-owned keychain
service `org.dashfoundation.dash`. They never delete the service, PIN, chain
lists, or unrelated records.

All new writes go to SDK-owned persistence:

- `PlatformWalletManager` / SwiftData for managed-wallet rows;
- SwiftDashSDK `WalletStorage` for mnemonic bytes keyed by SDK wallet ID;
- `WalletEnvironment` UserDefaults entries for the active wallet per network.

DashSync mnemonic entries remain a recovery/rollback source until the user
explicitly removes the corresponding wallet.

## Frozen DashSync keychain contract

Only compatibility code may know these old layouts:

| Data | Service | Account | Format |
|---|---|---|---|
| Mnemonic | `org.dashfoundation.dash` | `WALLET_MNEMONIC_KEY_<dashSyncWalletID>` | UTF-8 BIP39 phrase |
| Wallet list per chain | `org.dashfoundation.dash` | `CHAIN_WALLETS_KEY_<genesisShortHex>` | NSKeyedArchiver array of DashSync wallet ID strings |
| Extended-public-key cache | `org.dashfoundation.dash` | `<pathReference>_<dashSyncWalletID>` | Raw `NSData`; not imported |

DashSync wallet IDs are short hash strings. SDK wallet IDs are 32-byte SDK
identifiers and are not expected to match.

DashSync loaded wallets only from the per-chain lists. Its Reset
(`DSChain.unregisterWallet`) rewrites the list without the wallet ID (an empty
array for the last wallet) and deletes the PIN, but never deletes the wallet's
`WALLET_MNEMONIC_KEY_*` account. A mnemonic that no list names is therefore a
wallet the user reset in the previous app, which that app no longer showed
either: an **orphaned mnemonic**.

Known chain suffixes:

| Network | Genesis short hex |
|---|---|
| Mainnet | `b67a40f` |
| Testnet | `2cbcf83` |

## Current migrator algorithm

`SwiftDashSDKKeyMigrator.migrateIfNeeded()` returns immediately and performs the
work on a background queue:

1. If `swiftSDKKeyMigration.v1.done` exists, return.
2. Clear stale legacy defer flags and enumerate the service's accounts
   (attributes only).
3. If no `WALLET_MNEMONIC_KEY_*` account exists, mark migration done (fresh
   install or already wiped device).
4. Read every `CHAIN_WALLETS_KEY_*` list, one item at a time. If any list
   cannot be read or decoded, set `deferredFailure` and stop: a list that
   cannot be read might name any wallet.
5. For each DashSync wallet ID not already present in the success ledger,
   classify it against the lists (`DashSyncChainWalletLists`):
   - orphaned (every list read, none names it): skip it. It stays in the
     keychain, neither migrated nor deleted;
   - listed only by an unsupported chain, or no chain list exists at all:
     unknown chain;
   - listed on mainnet or testnet: read and validate the mnemonic,
     sanity-check deterministic seed derivation, call
     `SwiftDashSDKHost.createOrImportWallet` on the main actor, and persist
     the DashSync wallet ID in
     `swiftSDKKeyMigration.v1.migratedDashSyncWalletIds`.
6. Set the done sentinel only when every discovered wallet migrated, was
   already in the ledger, or is orphaned, and no wallet has an unknown chain or
   failure.
7. Notify `SwiftDashSDKWalletRuntime` after the done sentinel is written.
8. Every run past step 1 writes one summary line with counts, never wallet
   IDs, to the app log, so diagnostic exports show the outcome (the
   migrator's os_log lines do not reach them).

Partial runs are resumable: successfully migrated wallet IDs are not imported
again, while failures are retried on a later launch.

The launch decision (`legacyWalletMaterialState()`) applies the same
classification before the run finishes: a keychain holding only orphaned
mnemonics is absent, so setup is offered at once; any listed or unresolved
mnemonic is pending, and the launch hold waits for the migrator; a keychain or
chain-list read failure is unreadable, and the hold fails closed.

## Multi-wallet behavior

Multiple DashSync wallets are supported. The old
`swiftSDKKeyMigration.v1.deferredMultiWallet` flag is legacy compatibility
state: the current migrator clears it and does not use it as a skip condition.

After wallets load, `SwiftDashSDKHost` resolves the active wallet using
`WalletEnvironment.activeWalletId(for:)`, scoped independently to mainnet and
testnet. If the recorded ID is absent, the manager selects its deterministic
`firstWallet` fallback and persists that choice.

Create/import/switch/remove and network-mirror code must always resolve by the
active wallet ID. Selecting `persistedMnemonics().first` is forbidden when more
than one wallet exists; that previously mirrored or displayed the wrong wallet.

## Incomplete cases

| Condition | Behavior |
|---|---|
| Wallet ID listed only by an unsupported DashSync chain (devnet/regtest/evonet) | Set `swiftSDKKeyMigration.v1.deferredUnknownChain`; leave done unset; retry later. |
| Mnemonics exist but no `CHAIN_WALLETS_KEY_*` list exists at all | Same as an unsupported chain: fail closed. A real Reset keeps its (emptied) list, so no list at all is a layout the migrator cannot vouch for. |
| A chain list cannot be read or decoded | Set `swiftSDKKeyMigration.v1.deferredFailure`; leave done unset; retry later. The launch probe reports the keychain unreadable. |
| Mnemonic missing/invalid or host creation fails | Leave done unset; retain successes in the per-wallet ledger; retry later. |
| No old mnemonics, or only orphaned ones | Mark done so SDK runtime startup does not wait indefinitely. Orphaned mnemonics stay in the keychain. |

The runtime treats legacy defer flags as permission to stop waiting, but the
migrator remains responsible for clearing stale values and retrying incomplete
work.

## Host recovery behavior

If SwiftData wallet rows are missing but SDK-owned mnemonic entries remain,
`SwiftDashSDKHost.recoverPersistedWallet` recreates only wallets whose stored
ID belongs to the runtime network. It never stores a mainnet mirror from a
testnet ID or vice versa, and rejects a created ID that differs from the
stored source ID.

Create/import derives the deterministic SDK wallet ID, stores and verifies the
SDK-owned mnemonic under that ID, and only then creates the live managed
wallet. A Keychain persistence failure therefore cannot leave a live seedless
wallet; a later manager-creation failure removes only the provisional mnemonic.

## Wipe contract

The SDK wiper deletes SDK-owned mnemonics and managed-wallet state through a
manager bound to each wallet's mainnet/testnet store. It reports success only
after the global SDK mnemonic inventory is empty.

PIN removal, metadata deletion, app/global preference reset, CrowdNode cleanup,
active-wallet registry cleanup, and runtime teardown happen only after that
success point and before the serial-queue completion barrier fires. A failed
full wipe preserves those app-owned stores so the user can retry. Per-wallet
state belonging to a wallet already deleted successfully may be cleared with
that wallet during a partially successful attempt.

Every wipe entry point waits for the same explicit result before navigating or
creating a replacement wallet. Production recovery removes only the legacy
mnemonic accounts matching its single authorized SDK seed; confirmed Delete
All removes every legacy mnemonic account, orphaned ones included. Both run
before SDK deletion, and a
cleanup failure aborts the SDK wipe. Debug reset and screenshot replacement
preserve legacy data. The app never deletes the whole
`org.dashfoundation.dash` service.

Per-wallet Remove deletes matching legacy mnemonic accounts, then the
deterministic mainnet and testnet SDK IDs for that seed, with the live network
last. The old `CHAIN_WALLETS_KEY_*` lists may retain harmless IDs whose
mnemonic is gone: they contain no seed and the migrator only starts from
mnemonic accounts. The reverse, a mnemonic that no list names, is an orphaned
mnemonic (see the frozen contract above).

A Wallets-screen Remove may route into the global wipe only after Keychain
ground truth proves every stored wallet ID belongs to the same recovery phrase
as the target; the currently rendered row count is not an authoritative
last-wallet check. Enumeration or any individual mnemonic-read failure denies
that route. A sole rendered wallet whose removal cannot route to the reset
flow is refused up front with an explanation, rather than walked into a
per-wallet removal that must fail (per-wallet removal always leaves a wallet
to switch to, enforced independently of the active-wallet registry).

Recovery-phrase authorization on the recover-screen wipe path is set-wide: the
typed phrase must match every stored mnemonic, and any unreadable entry (or an
enumeration failure) denies authorization outright — a partially readable
Keychain never authorizes. Multiple network-scoped IDs for the same phrase are
allowed. A phrase that matches some but not all stored wallets is refused with
copy that says so (it is not reported as a phrase mismatch). The plain `wipe`
shortcut is allowed only with exactly one stored wallet ID and only while the
active network is mainnet, because the published balance is scoped to the
active wallet/network and cannot prove a mainnet balance while running on
testnet. The support acknowledgement is accepted only by the separate Support
Wipe path. Forgot-PIN recovery stays non-destructive and may prove ownership
with any one stored wallet phrase.

Every call to `DWSwiftDashSDKWalletWiper` supplies an explicit authorization
reason. Ordinary recovery-screen wipes use `.recoveryFlow`; Support Wipe uses
`.confirmedDeleteAll`; screenshot-triggered replacement uses
`.screenshotReplacement`; and the dev-only reset uses `.debugReset`.
Post-reinstall and lock-screen Delete All warnings deliberately omit an SDK-only
count because the operation may also remove legacy-only seeds. Any new wipe
entry point must collect one of these authorizations before invoking the wiper.

## Acceptance criteria

- one and multiple DashSync wallets import without selecting the wrong active
  wallet;
- a partial failure resumes without duplicating successful wallets;
- a mnemonic orphaned by a DashSync Reset neither holds the launch nor blocks
  the done sentinel, and stays in the keychain;
- an unreadable or undecodable chain list, a keychain without any chain list,
  and an unsupported chain all keep the launch hold (fail closed);
- mainnet and testnet retain separate active-wallet choices;
- create/import/recovery use the same host boundary;
- create/import persist and verify the mnemonic before the wallet becomes live;
- network switch mirrors only the active wallet while the legacy shim exists;
- a hidden or unrestorable second wallet cannot make a row-level Remove route
  into the global wipe;
- one wallet's recovery phrase cannot authorize a global wipe while a distinct
  wallet is stored, and active-network zero balance cannot authorize one while
  any additional wallet ID is stored or while the active network is testnet;
- a successful wipe deletes all SDK-owned mnemonic/managed-wallet/active-wallet
  state, while a failed wipe reports failure without an app-side seed deletion;
- normal migration never deletes legacy entries; explicit production Remove
  and Delete All delete only the intended legacy mnemonic accounts;
- both app schemes build and upgrade/multi-wallet/wipe runtime smokes pass.

## Source files

- `DashWallet/Sources/Infrastructure/SwiftDashSDK/SwiftDashSDKKeyMigrator.swift`
- `DashWallet/Sources/Infrastructure/SwiftDashSDK/WalletLifecycleTransitionState.swift`
  (`DashSyncChainWalletLists`, the launch hold)
- `DashWallet/Sources/Infrastructure/SwiftDashSDK/SwiftDashSDKHost.swift`
- `DashWallet/Sources/Infrastructure/SwiftDashSDK/WalletEnvironment.swift`
- `DashWallet/Sources/Infrastructure/SwiftDashSDK/SwiftDashSDKWalletRuntime.swift`
- `DashWallet/Sources/Infrastructure/SwiftDashSDK/SwiftDashSDKWalletWiper.swift`
