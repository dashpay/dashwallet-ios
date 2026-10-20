# Reference wallet preparation

Fixture ID: `testnet-restore-mixed`. Fixture format version: `1`.
Preparation status: **PARTIAL — BLOCKED** (2026-10-20).
First successful restore: **NOT RUN**.
The wallet exists, but successful shielding and withdrawal are missing.
Observed preparation balances below are not a ready restore fixture or baseline.

This dedicated testnet wallet will contain ordinary and shielded funds. Prepare
it once, then reserve it for restore tests. Preparation is a separate operator
session; asking an agent to run the restore scenario does not authorize funding
or transactions. Use testnet funds only, never an existing personal wallet.

## Secret handling

Reserve the macOS Keychain service `org.dash.wallet.qa` and account
`testnet-restore-mixed-v1` for its recovery phrase. These are identifiers, not
credentials. The item was created locally on 2026-10-20. The operator stores and retrieves
the phrase through a trusted local interface and enters it manually during
restore. Do not pass it through chat, agent tool output, command arguments,
environment variables, files, screenshots, or reports. Other operators provision
their own Keychain item through an agreed secure handoff outside this repository.

## Current preparation checkpoint

The app created a new wallet on a dedicated simulator and its phrase was saved
in the Keychain item above. The one-time preparation used an in-memory transfer
through the native UI; the phrase was not emitted in tool output or saved in
files, logs, screenshots, or this repository. Routine restores still use the
operator-assisted procedure.

The in-app faucet provided 1 tDash. A normal Core self-transfer of 0.1 tDash
succeeded. This covers a transparent spend and change, not payment to a separate
wallet. Shielding 0.4 tDash then created a Core asset lock, but Platform rejected
the next step: `ShieldFromAssetLock` is no longer accepted at protocol version 14;
the response says version 13 was the last to accept this transition type.
The app shows **Pending — tap to finish**. No shielded funds were credited and
no withdrawal was attempted. The restore scenario is blocked at fixture preflight.

Confirmed Core operations observed in the preparation wallet:

| Operation | Transaction ID | Amount and actual Core fee |
| --- | --- | --- |
| Faucet receive, height 1575931 | `b49ef78b6f378816d1f20eccce0c38bfff367ac012fe2e53a6507bf6ac934740` | Received 100,000,000 duffs; faucet-paid fee not established |
| Self-transfer, height 1575932 | `759428909557fafd3ee8d8996885639222ce4cd6c2904ac45e2f936a2eb6b4c4` | Principal 10,000,000 duffs stays in this wallet; fee 226 duffs |
| Pending shielding asset lock, height 1575932 | `9e873498aeb189d63942322fb69710a9aa14f288cc54d26547663567314b2d41` | Locked 40,212,852 duffs; Core fee 263 duffs; Platform fee not finalized |

At 2026-10-20 07:52 UTC, the preparation store contained two confirmed, unspent,
unlocked Core outputs totaling **59,786,659 duffs**, a pending asset lock of
**40,212,852 duffs**, and **zero shielded notes / zero credits**. These reconcile
as 100,000,000 − 226 − 263 − 40,212,852 = 59,786,659 duffs.
The attempted shield principal was 40,000,000 duffs; do not treat the larger
asset-lock amount or its estimated Platform overhead as a successful shield.
The receive/self-transfer address is `yebQWeLYDnjhjBwQfRe6FFE22GGpAR1aRH`.
The preparation store records block 1575932 as
`000000e8c9dbbf8ded9313361fac389f5c4d4b7b96fec65f23db904748da72ca`;
this is local confirmation evidence, not an independently verified fixture anchor.

Retain the preparation simulator and its app storage to finish the pending
asset lock after selecting an SDK compatible with the live testnet protocol.
Do not repeat funding or shielding blindly, erase that simulator, or mark the
fixture ready. Record any dependency update and continuation as a new preparation
attempt, then complete withdrawal and a fresh restore before establishing a baseline.

Build used for this unsuccessful preparation (not a successful restore reference):

- App: [dashpay/dashwallet-ios](https://github.com/dashpay/dashwallet-ios/commit/67664632ac60374be9b5e928a2610961e4c8357a),
  `67664632ac60374be9b5e928a2610961e4c8357a`; no application source changes.
- Platform and app `.platform-ref`:
  [dashpay/platform](https://github.com/dashpay/platform/commit/2f4d161c89bd1750a5cc2ceef391e1cee192a9a7),
  `2f4d161c89bd1750a5cc2ceef391e1cee192a9a7`; clean checkout.
- rust-dashcore resolved in `Cargo.lock`:
  [7302d0a6eb8770f5b1cb000363afdf8b86c67ce7](https://github.com/dashpay/rust-dashcore/commit/7302d0a6eb8770f5b1cb000363afdf8b86c67ce7).
  Crates: `dash-network`, `dash-network-seeds`, `dash-spv`, `dashcore`,
  `dashcore-private`, `dashcore-rpc`, `dashcore-rpc-json`, `dashcore_hashes`,
  `git-state`, `key-wallet`, `key-wallet-ffi`, `key-wallet-manager`.
  No local rust-dashcore override was used.
- `Cargo.lock` SHA-256:
  `0613167bb16894d0e564831a692b768716dbfb987cd0a88cd134189904556074`.
- Framework built from that Platform checkout using
  `SKIP_EXAMPLE_APP_BUILD=1 CARGO_BUILD_JOBS=6 bash build_ios.sh --target sim --profile release`.
  `DashSDKFFI.xcframework/ios-arm64-simulator/librs_unified_sdk_ffi.a` SHA-256:
  `8199c5bdcb1200f6816cd515a2788cd8edeb11ba412ec7448d8826e19a127605`.
- App build: `dashpay`, Debug, arm64 simulator; bundle `org.dashfoundation.dash`.
  Both framework and app builds succeeded. Environment: arm64 macOS 26.6.2,
  Xcode 26.6 (17F113), iPhone 17 / iOS 26.5 (23F77).
- Testnet was explicitly selected before wallet creation with launch arguments
  `-CURRENT_CHAIN_TYPE_KEY 1`, and the UI showed `TESTNET`. Repeat those
  arguments on relaunch; this does not establish a persisted network preference.

Full provenance, selected database evidence, and the blocked report stay under
ignored `qa-results/`. They are local evidence, not committed baseline results.

## One-time preparation

1. Select clean app/platform revisions and record build provenance as described
   in [README.md](README.md). Explicitly select testnet, create the new wallet in
   a dedicated simulator, and store the phrase in Keychain without capture.
2. Record account/derivation scope and scan start. Receive testnet funds from an
   operator-selected faucet or test wallet. Size funding and subsequent transfers
   from actual fee estimates so ordinary and shielded balances remain positive;
   do not hardcode guessed fees or spend a maximum amount.
3. Send part of the ordinary funds to an operator-controlled testnet recipient,
   shield part of the remaining funds, then withdraw part of the shielded funds
   back to this wallet's Core address. Use the app's supported flows. Record each
   actual amount, fee (or explicitly unavailable fee), transaction/transition ID,
   confirmation evidence, and resulting balance. Preserve preparation evidence
   under its own ignored `qa-results/` directory.
4. Wait for operations to settle. Record Core height/hash, Platform height/hash,
   and the relevant shielded commitment boundary, including the source and
   meaning of each watermark. Capture exact final balances and their categories.
5. Establish expected facts from confirmed preparation receipts, network evidence
   where observable, and the preparation wallet's state. Shielded values require
   wallet-side evidence; do not pretend a public explorer reveals them. Reconcile
   transfers and fees, with explicit unit conversions. An unexplained discrepancy
   means preparation is incomplete.
6. Perform a fresh restore using the scenario. Require exact known balances and
   recoverable history, then verify relaunch. Document which shielded details are
   recoverable without assuming original labels, dates, fees, or row grouping.
   Do not redefine correctness simply to match what the restored app displays.
7. After operator review, fill the records below and set status to `READY` with a
   fixture version. Record the first successful build metadata. Full reports stay
   ignored; only reviewed non-secret fixture facts and the compact build record
   belong in Git. Committing still requires explicit permission.

## Fixture facts to complete

Every `NOT RECORDED` entry below is a missing prerequisite, not an example value.

| Field | Value |
| --- | --- |
| Fixture data version and preparation UTC date | NOT RECORDED |
| Account indexes, derivation scope, scan start | NOT RECORDED |
| Public testnet addresses needed for checks | NOT RECORDED |
| Core anchor height and block hash, evidence source | NOT RECORDED |
| Platform anchor height and block hash, evidence source | NOT RECORDED |
| Shielded commitment boundary and index semantics | NOT RECORDED |
| Expected Core total/spendable/unconfirmed balances in duffs | NOT RECORDED |
| Expected shielded balance categories in native integer credits | NOT RECORDED |
| Other nonzero balance categories and their units | NOT RECORDED |
| Last fixture activity and confirmation evidence | NOT RECORDED |

| Required operation | ID and confirmed anchor | Actual principal and fee with units | Facts required after restore and evidence source |
| --- | --- | --- | --- |
| Ordinary receive | NOT RECORDED | NOT RECORDED | NOT RECORDED |
| Ordinary send | NOT RECORDED | NOT RECORDED | NOT RECORDED |
| Shielding | NOT RECORDED | NOT RECORDED | NOT RECORDED |
| Partial withdrawal to Core | NOT RECORDED | NOT RECORDED | NOT RECORDED |

Require exact balances and the operation facts established above; a total UI row
count is only an observation unless its grouping and scope are explicitly defined.
Record amounts in their native integer units. The current UI converts 1,000 credits
to 1 duff; rounded display amounts cannot establish exact shielded equality.

## First successful restore metadata

This compact record identifies the original working combination, not a golden
performance result or proof that all later versions are correct.

| Field | Value |
| --- | --- |
| Successful run ID, UTC date, reviewer | NOT RECORDED |
| Scenario version and fixture data version | NOT RECORDED |
| App repository URL, full SHA and commit link | NOT RECORDED |
| Platform repository URL, full SHA and commit link | NOT RECORDED |
| App platform pin and actual resolved package location | NOT RECORDED |
| Effective rust-dashcore sources, full SHAs, crate mapping, overrides | NOT RECORDED |
| Cargo.lock SHA-256 and clean source verification | NOT RECORDED |
| Framework build command/profile and source provenance | NOT RECORDED |
| Simulator library relative path and SHA-256 | NOT RECORDED |
| App build command/configuration and bundle identifier | NOT RECORDED |
| Mac, macOS, Xcode, Rust, simulator and agent/tool versions | NOT RECORDED |

Keep this first record unchanged when testing another revision. If the fixture
receives new funds, is spent from, or its anchors are replaced, explicitly prepare
a new data version before expecting exact equality again. A routine test must
report this drift rather than silently updating the fixture.
