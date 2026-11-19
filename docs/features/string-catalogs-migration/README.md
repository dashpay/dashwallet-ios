# String Catalog migration

**Owner:** romchornyi

## Why

The main app kept its texts in per-locale `Localizable.strings` / `Localizable.stringsdict` lists,
kept in step by BartyCrouch. Xcode's String Catalog replaces both with one file that the compiler
keeps in step with the code.

## What changed

- **One String Catalog** — `DashWallet/Localizable.xcstrings` holds the main app's texts in all 43
  locales; the app ships 22 of them. The Catalog was generated from the old lists.
  [ADR-0065](../../adr/0065-generate-the-catalog-from-the-baseline-lists-with-a-repository-script.md).
- **Swift looks texts up with `String(localized:)`**; a text with arguments became an interpolation and
  its entry moved to the new key in every locale. Objective-C keeps `NSLocalizedString`.
  [ADR-0066](../../adr/0066-rewrite-formatted-lookups-as-interpolations-and-move-their-entries.md),
  [ADR-0069](../../adr/0069-rewrite-swift-lookups-with-a-swiftsyntax-codemod-rerun-on-every-baseline.md).
- **Debug builds keep the Catalog in step with the code** through a "Sync String Catalog" build phase.
  [ADR-0068](../../adr/0068-keep-the-catalog-in-step-with-xcodes-own-string-sync-in-every-build.md),
  [ADR-0071](../../adr/0071-make-the-sync-phase-write-the-same-catalog-as-the-xcode-app.md).
- **A zero-loss check** (`scripts/localization/zero_loss_check.py`) proves that every text reads as
  before in every locale; it stays in the repository for the release re-checks. How to run it:
  [`scripts/localization/ZERO_LOSS_CHECK.md`](../../../scripts/localization/ZERO_LOSS_CHECK.md).
  [ADR-0064](../../adr/0064-declare-the-app-and-the-zero-loss-check-as-the-feature-surfaces.md),
  [ADR-0067](../../adr/0067-prove-zero-loss-by-pairing-each-code-place-with-its-baseline-key.md),
  [ADR-0070](../../adr/0070-check-releases-through-the-key-map.md).

## What it guarantees

- Every screen shows the same wording in every locale as before the move, counted phrases included.
- CI fails when Swift code uses `NSLocalizedString` or a build changes the checkout.
