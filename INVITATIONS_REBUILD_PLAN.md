# DashPay Invitations Rebuild Plan (T1: port)

Resolves teardown item T1 in `DASHSYNC_TEARDOWN_PLAN.md` as **port** (not delete):
rebuild invitations on SwiftDashSDK, delete the DashSync invitation subsystem in
the same change, cross-platform-compatible with Android's shipping
implementation (dash-wallet master, dashj/dpp stack).

Readiness basis (surveyed 2026-07-16):

- SDK (`../platform` @ `v4.1-dev`): create/parse/claim/reclaim + SwiftData
  persistence are implemented and exercised by the SDK example app.
  Key APIs: `ManagedPlatformWallet.createInvitation(amountDuffs:fundingAccount:inviterIdentityId:inviterUsername:nowUnix:)`,
  `parseInvitation(uri:)`, `claimInvitation(uri:identityIndex:identityPubkeys:signer:nowUnix:)`,
  `resumeIdentityWithAssetLock(...consumeInvitationVoucher:)`,
  `resumeTopUpWithAssetLock(...consumeInvitationVoucher:)`; model
  `PersistentInvitation` (registered in `DashModelContainer`). Derivation is
  DIP-13 `m/9'/coinType'/5'/3'/index'` — matches Android's
  `INVITATION_FUNDING` keychain, so restored wallets reconstruct the same
  vouchers on both platforms.
- Android (shipping on mainnet): link contract `dashpay://invite?du=…&assetlocktx=…&pk=…&islock=…[&display-name=…][&avatar-url=…]`,
  AppsFlyer OneLink distribution (`dashpay.onelink.me` prod /
  `dashpaytest.onelink.me` testnet, payload round-trips via `af_dp`), fee tiers
  0.25 DASH (contested-capable, default) / 0.03 DASH, recipient minimum
  0.003 DASH, claimed-detection by polling whether an identity exists for the
  voucher outpoint, post-claim auto contact request to the `du` inviter.
  Android has no reclaim.

## Product decisions (confirm before/while building)

| # | Decision | Recommendation |
|---|---|---|
| P1 | Offer reclaim of unclaimed invitations (SDK supports it; Android doesn't)? | Yes, behind the history screen — value returns as **identity credits** (new identity or top-up), never L1 Dash; copy must say so. Defer if scope-cutting. |
| P2 | Fee tiers | Mirror Android: 0.25 (contested allowance, default) / 0.03. Requires S1. |
| P3 | Distribution model | **Decided (2026-07-16): paste/scan-first, no third parties, no hosting.** Invites are shared as the raw `dashpay://invite` URI + QR; the invitee installs the app, then redeems by QR scan or paste. No AppsFlyer SDK (closed-source binary; bearer key would transit their servers), no OneLink, no hosted landing page. A static fallback page on `invitations.dashpay.io` (AASA/assetlinks already live there) remains a purely additive later enhancement — the link format doesn't change. |
| P4 | Claimed-status copy | Watcher-based "Claimed" (parity with Android, see A5); status may lag platform polling. |

## S. Upstream SDK changes (`../platform`, land on `v4.1-dev`)

Per the platform-pin rule, these go upstream first; the app consumes a rebuilt
xcframework (`./build_ios.sh --target ios --target sim`).

- **S1 — raise the create cap.** `MAX_INVITATION_DUFFS = 5_000_000` (0.05) in
  `rs-platform-wallet/src/wallet/identity/network/invitation.rs` blocks
  Android's 0.25 contested tier. Raise to ≥ `25_000_000` (or make the bound a
  caller parameter). Verify the **claim** path has no equivalent upper bound so
  0.25 Android invites claim cleanly on iOS regardless.
- **S2 — none otherwise.** `du`-optionality, big-endian txid, `islock="null"`
  tolerance, and network-typed WIF are already Android-compatible. iOS simply
  always supplies `inviterIdentityId`+`inviterUsername` (A2) because Android's
  parser requires `du`.

## A. App-side work (dashwallet-ios)

### A1. Invitation service (new, `Sources/Infrastructure/SwiftDashSDK/Invitations/`)

`DWInvitationService` behind a protocol seam (guardrail #4), injected where
possible; resolves the wallet via `SwiftDashSDKHost` (never ad-hoc
`WalletStorage()`); `@MainActor` published state for the UI.

- `createInvitation(amount: UInt64) async throws -> String` — requires a
  registered local username (source of `du`); wraps
  `ManagedPlatformWallet.createInvitation`, funding account = the core BIP44
  account index used by `.core` registration.
- `parse(_ uri: String) throws -> InvitationPreview` — passthrough.
- `invitations` — SwiftData `@Query`/fetch over `PersistentInvitation` filtered
  by active `walletId`.
- `normalize(_ url: URL) -> String?` — link unwrap (A4): accepts
  `dashpay://invite`, OneLink URLs (extract `af_dp`), and legacy
  `invitations.dashpay.io/applink`; returns the inner `dashpay://invite` URI
  for `parseInvitation`.
- Reclaim (P1): `reclaimIntoTopUp(_:)` / `reclaimIntoNewIdentity(_:)` with
  `consumeInvitationVoucher: true`, mirroring the SDK example app's
  `ReclaimInvitationSheet` failure classifier (foreign-claim vs own
  interrupted reclaim via the `reclaimInFlight` marker).

### A2. Create flow

Replaces `DWConfirmInvitationViewController.m`'s
`createBlockchainInvitation`/`registerOnNetwork:` machinery with one
`createInvitation` call. Notes:

- Gate on `SyncingActivityMonitor` `.syncDone` (never SPV `state == .synced`)
  and on local identity registered + spendable balance ≥ selected tier.
- Auth via `AuthenticationGate` before building; the SDK call broadcasts — the
  confirm screen therefore shows amount + fee **before** invoking it (`prepare`
  never broadcasts rule applies to the UI contract: no broadcast until the
  user's explicit confirm tap invokes the service).
- The SDK waits for the InstantSend proof and only then returns the link; the
  voucher row is persisted before the wait, so an interrupted create surfaces
  in history as reclaimable rather than lost. Show a "waiting for confirmation"
  phase.
- The returned URI embeds the bearer voucher key: never log it, never persist
  it app-side (the SDK model stores no secret), share-sheet/QR/copy only.

### A3. Accept (claim) flow

- Entry plumbing **reused as-is**: `DWAppRootViewController.handleDeeplink:` →
  `DWInvitationSetupState` stash (no wallet / locked) →
  `HomeViewController.handleDeeplink(_:definedUsername:)`.
- `DWDashPayModel.verifyDeeplink:` (DashSync) is replaced by
  `DWInvitationService.parse` + an "already claimed?" platform lookup
  (identity exists for the voucher outpoint) before showing the accept UI —
  states mirror Android: valid / already-have-identity / already-claimed /
  invalid / not-synced.
- Claim executes inside `DWIdentityRegistrationCoordinator` so it inherits the
  PIN gate, `prePersistIdentityKeysForRegistration`, `registerDpnsName`,
  `DWRegistrationPhaseAdapter` phases, retry/cancel, and the
  `DWGlobalOptions` mirror. Because `DWIdentityFundingSource` is an `@objc`
  Int enum (no associated values), add a Swift-only entry point
  `startCreateUsername(_ username: String, claimingInvitation uri: String)`
  that routes the funding switch to `wallet.claimInvitation(...)`; the Int
  enum gains `case invitation = 3` for phase/logging only. The caller is Swift
  (`HomeViewController`) — do not extend the ObjC bridge for this;
  the `showCreateUsername(withInvitation:)` shortcut regains a real
  invitation path (it currently drops the URL, passing `invitationURL: nil`).
- Post-claim contact-request bootstrap (Android parity): resolve `du` via DPNS,
  send a contact request through the existing SDK contacts stack from #787.
  Failure here must not fail the claim — surface as a soft retry.
- Claim replaces the shielded/core funding choice for this registration; the
  JoinDashPay readiness screens are bypassed when an invitation is present.

### A4. Link distribution (paste/scan-first, no third parties — P3)

- **Share side**: the share sheet offers the raw `dashpay://invite` URI as text
  plus an app-rendered QR code (~600 chars, islock hex dominates; well within
  QR capacity). No wrapping, shortening, or third-party upload — the URI is a
  bearer instrument and never leaves the two devices except via the user's own
  chosen channel. Suggested message template: install link (App Store /
  Play Store) + the invite code.
- **Redeem side**: a "Have an invitation?" entry point in onboarding and in the
  create-username flow — paste field + the existing QR-scanner component. The
  input goes through `DWInvitationService.normalize` (A1), which accepts the
  raw `dashpay://invite` URI, the legacy `invitations.dashpay.io/applink` form,
  and pasted Android OneLink long-URLs (unwraps `af_dp`) — so Android-generated
  invites redeem on iOS via paste with no AppsFlyer SDK.
- **First-launch pasteboard check**: if the invitee copied the invite before
  installing, offer redemption on first launch via the iOS paste-permission
  prompt (deferred deep linking with no third party; degrades to manual paste
  if declined).
- Remove `pod 'Firebase/DynamicLinks'` (both targets) and the `FIRDynamicLinks`
  code in `AppDelegate.m` `continueUserActivity:` / `openURL:` — the service
  was shut down in 2025; today this code silently eats universal links.
- Registration/config additions:
  - Info.plist: add `dashpay` to `CFBundleURLSchemes` (Android registers
    `dashpay://` and `dashwallet://`; iOS currently registers only
    `dash`/`dashwallet`/`pay`/`dashid`). With the app installed, a tapped raw
    link opens directly wherever messengers linkify it.
  - Entitlements: keep the existing `applinks:invitations.dashpay.io` (its AASA
    is still live and lists our bundle IDs, so legacy-form links open the app
    when installed). No OneLink domains added.
  - `DWURLParser.canHandleURL:` gains the `dashpay` scheme, routed to the
    invite handler (not the payment parser).

### A5. History + claimed-status watcher

- SwiftUI history screen over `PersistentInvitation` (newest-first, active
  wallet only), statuses Created / Claimed / Reclaimed.
- The Rust layer only ever emits `Created`. Adopt Android's semantics: a
  lightweight watcher (`SyncingActivityMonitor`-gated, piggybacking on the
  existing platform polling cadence) checks each `Created` invitation for an
  identity at the voucher outpoint's derived identity ID and flips local
  status to `Claimed`, also resolving the claimant's profile for display.
  Reclaim success (P1) sets `Reclaimed` (or `Claimed` on the
  "already consumed" consensus error), as the SDK example app does.
  Status honesty per guardrail #3: rows are "Created" until *observed*
  claimed — no fabricated freshness.

### A6. SwiftUI screen set (all with `@MainActor` ViewModels; no FFI in views)

| Screen | Replaces |
|---|---|
| `InvitationHistoryScreen` + rows/filter | `DWInvitationHistoryViewController` + cells/filter stack |
| `CreateInvitationScreen` (intro + fee-tier picker P2) | `DWSendInviteFirstStepViewController`, `InvitationFeeDialog` (Android analog) |
| `ConfirmInvitationSheet` (amount/fee, checkbox) | `DWConfirmInvitationViewController` + content view |
| `InvitationShareScreen` (QR, copy, share sheet, tag/memo) | `BaseInvitationViewController` / `SuccessInvitationViewController` + card views |
| `ClaimInvitationScreen` (preview → username form → progress) | `DWDashPayModel` accept arm + `DWInvitationPreviewViewController` |
| `RedeemInvitationEntry` (paste field + QR scan; onboarding + create-username; A4) | — (new; replaces link-only entry) |
| `ReclaimInvitationSheet` (P1, credits-only messaging) | — (new; SDK example app is the reference) |

Localization: the 37 restored contacts/invitations keys (commit `bc5383381`)
cover the legacy copy; new screens may add keys — keep `en` UTF-8, alphabetical.

### A7. Deletion list (same change as the port — T1 rule, no disabled legacy)

- `DashWallet/Sources/UI/DashPay/Invites/**` (flow controller, first-step,
  confirmation, history, preview, invitation views, link builder, alert
  additions) — all targets' pbxproj membership, xibs, bridging-header entries.
- `DWDashPayModel.m`: `verifyDeeplink:`, `createUsername:invitation:`
  invitation + existing-identity DashSync arms,
  `sendContactRequestToInviterUsingInvitationURL:`, `invitationSteps`,
  `DSBlockchainInvitation`/`DSIdentitiesManager` imports.
- `DWHomeModel.handleDeeplink:` DashSync passthrough (retarget to the service).
- `Firebase/DynamicLinks` pods + `FIRDynamicLinks` AppDelegate code (A4).
- Mock invitation paths (`createBlockchainIdentity(forUsername:)` mock usage in
  `BaseInvitationViewController`).
- **Keep**: `DWInvitationSetupState` (DashSync-free stash), the root-VC
  deep-link replay, `menu_invite` / `icon_invitation_error` assets, restored
  l10n keys.
- Grep gate after deletion: `DSBlockchainInvitation` must have zero hits
  outside DashSync itself (teardown plan §163 guard).

### A8. Docs (same change)

- `DASHSYNC_MIGRATION.md`: row 16 tail → invitation-funded create/accept
  migrated; current-state list item 1 shrinks to the legacy profile-view
  compatibility types (which remain a separate cleanup).
- `DASHSYNC_TEARDOWN_PLAN.md`: T1 decision recorded as "ported"; remaining
  T1 scope reduced to the profile/`JoinDashPayViewModel` compatibility reads.

## Sequencing

1. **PR-0 (platform, `v4.1-dev`)**: S1 cap raise + claim-path bound check.
2. **PR-1 (app)**: A1 service + A3 claim path + A4 link plumbing + claim UI;
   DashSync accept arm deleted with it.
3. **PR-2 (app)**: A2/A6 create + history + share UI (+P1 reclaim), the A5
   claimed-status watcher (it needs the outpoint→identityId derivation and
   only has meaning once the history UI displays statuses), remaining
   deletions (A7) and docs (A8). Invitation code is DashSync-free at merge.

PR-1/PR-2 may be collapsed into one if review size allows; the T1 "same
change" rule binds deletion to the port of each arm, which both orderings keep.

## Verification

- `plutil -lint DashWallet.xcodeproj/project.pbxproj`; clean `dashpay` build
  (`ARCHS=arm64`, sim) — and `dashwallet` scheme build for the `#if DASHPAY`
  seams once compiling.
- Two-simulator **testnet** smoke (mainnet Platform DAPI is unreachable in the
  current SDK build; testnet-default posture stands): wallet A (registered
  username) creates a 0.03 invite → shares as text + QR; wallet B (fresh)
  redeems via **paste** (and once via the deep link with the app installed) →
  preview shows inviter → claims → username registered → contact request
  arrives at A. Then: B re-pastes the same invite → "already claimed";
  A reclaims an unclaimed invite (P1) → credits top-up; A's history flips the
  claimed row via the watcher. First-launch pasteboard offer verified once.
- Cross-platform: **paste an Android-generated OneLink invite** into iOS
  (normalizer unwraps `af_dp`) and open an iOS-generated raw link on Android
  (their `dashpay://` intent filter); confirms `du`-required, big-endian txid,
  and `islock` handling both directions. Tell the Android
  team their little-endian iOS shims (`TopUpRepository.kt:229,277,826`) can be
  retired once legacy iOS links are declared void (DashPay never shipped on
  iOS).
- Unit-test targets are still broken repo-wide; write link-normalization and
  watcher tests compile-ready per the existing convention.
