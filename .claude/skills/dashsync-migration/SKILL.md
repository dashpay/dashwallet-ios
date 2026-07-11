---
name: dashsync-migration
description: Use for DashSync removal, SwiftDashSDK migration, DWEnvironment teardown, key migration, or final pod-unlink work in dashwallet-ios. This is an endgame playbook: verify the current working tree, preserve upgrade contracts, remove bounded legacy tails, and keep migration/teardown docs current.
---

# DashSync removal endgame playbook

The broad functional migration is complete. Remaining work is teardown, not a
new staged rollout. Never infer status from old Shadow/Flipped/Solo labels or
raw `DS*` token counts.

## 1. Establish current truth

Read, in order:

1. the call sites and project configuration being changed;
2. `DASHSYNC_MIGRATION.md` for the current functional ledger;
3. `DASHSYNC_TEARDOWN_PLAN.md` for remaining unlink work;
4. `DASHSYNC_KEY_MIGRATION.md` for frozen upgrade contracts;
5. sibling `../platform/packages/swift-sdk/Sources/SwiftDashSDK/` and underlying
   FFI/Rust code when SDK behavior is relevant.

Docs are maintained snapshots, not substitutes for inspecting the working tree.
If code and docs disagree, verify the code, then update the docs in the same
change.

## 2. Classify the task

Every remaining DashSync dependency should fit one of these buckets:

- DashPay invitations or legacy identity/profile compatibility types;
- Apple Watch phone bridge/targets;
- C6-E wallet-registry compatibility (`DWEnvironment`, dual-write, wipe,
  `hasWallet`, chain-wallet notification, network mirror);
- non-wallet exported helpers (Uphold HTTP, generic keychain helpers,
  notifications, currency DTO, localization/utilities, startup);
- Podfile/pbxproj/resource/linker unlink mechanics.

Do not add a new adapter or dual-stack path without showing why deletion or a
direct app/SDK boundary cannot work.

## 3. Hard invariants

- The migration ships as one release; no production cross-library drift logic.
- Never delete old keychain entries in service `org.dashfoundation.dash`.
- The key migrator supports multiple wallets and resumes partial runs.
- Resolve wallet-sensitive work through the active wallet ID for the selected
  network; never choose the first mnemonic/wallet when several exist.
- Never read balance, UTXOs, transactions, sync state, or keys from frozen
  DashSync wallet objects.
- Every spend uses `WalletSendService` or the established SDK transaction
  sender boundary; UI code never builds/broadcasts directly.
- New Swift migration code imports `SwiftDashSDK`, never `DashSync`.
- Do not recreate SDK values as `DS*` objects merely to satisfy an old API;
  replace the boundary and delete the leaking legacy types.
- CrowdNode is temporarily suspended for the migration release and is not a
  DashSync teardown blocker. Never keep or reintroduce a DashSync path for it.
- `local/tx-decode-plus-v4.1-dev-dashwallet` is development-only. Required
  platform changes must land on `v4.1-dev`, and the final migration/release
  build must consume `v4.1-dev`.

## 4. Implementation rules

- Preserve ObjC selectors only when a thin SDK/app-owned bridge materially
  reduces churn; the bridge must expose non-DashSync types.
- Add new Swift files to both app targets when shared.
- Use top-level Infrastructure PBXGroup `479E7922287C00A000D0F7D7`.
- Remove obsolete sources, imports, bridging-header entries, pbxproj membership,
  resources, and Podfile dependencies in the same review-sized change.
- For invitation/Watch decisions, implement the chosen outcome end to end;
  do not leave disabled legacy code linked “for safety”.
- For generic keychain replacement, preserve exact service, account,
  accessibility, and byte encoding so Coinbase/Uphold/PIN state survives.

## 5. Audit gates

Prefer ownership-specific greps:

```bash
rg -n --glob '*.{h,m,mm,swift}' \
  '(#import[[:space:]]*[<\"][^\n]*DashSync|@import DashSync|^[[:space:]]*import DashSync)' \
  DashWallet DashPay TodayExtension WatchApp 'WatchApp Extension'

rg -n --glob '*.{h,m,mm,swift}' \
  '\b(DSChain|DSWallet|DSAccount|DSTransaction|DSBlockchainIdentity|DSBlockchainInvitation)\b' \
  DashWallet DashPay TodayExtension WatchApp 'WatchApp Extension'

rg -n "pod ['\"]DashSync|DashSync" Podfile Podfile.lock DashWallet.xcodeproj/project.pbxproj
```

Review remaining matches; a raw `DS[A-Z]` count includes app-owned names and
comments and is not a completion metric.

## 6. Verification

```bash
plutil -lint DashWallet.xcodeproj/project.pbxproj

xcodebuild -workspace DashWallet.xcworkspace -scheme dashwallet \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO EXCLUDED_ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES build

xcodebuild -workspace DashWallet.xcworkspace -scheme dashpay \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO EXCLUDED_ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES build
```

The SDK xcframework requires the arm64 simulator slice. After a platform branch
change, rebuild both device and simulator slices from
`../platform/packages/swift-sdk` with
`./build_ios.sh --target ios --target sim`.

For final verification, assert that `git -C ../platform branch --show-current`
returns `v4.1-dev`. A green build against the temporary integration branch is
development evidence only, not release completion.

Run focused runtime smokes proportional to the change. Upgrade/multi-wallet,
active-wallet network switch, wipe, auth, and retained invitation/Watch flows
cannot be proven by a build alone.

## 7. Documentation and handoff

In the same change:

- update the affected functional row in `DASHSYNC_MIGRATION.md`;
- remove closed work from `DASHSYNC_TEARDOWN_PLAN.md`;
- update `DASHSYNC_KEY_MIGRATION.md` when an upgrade/storage contract changes;
- update both `.codex` and `.claude` copies of this skill when the reusable
  procedure changes.

Keep docs present-state only. Staffing/ownership notes and session diaries do
not belong in technical status documents.

Per `AGENTS.md`, never commit or push without explicit user permission. Show the
diff or summarize changes and stop for review.
