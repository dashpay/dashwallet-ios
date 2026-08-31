# Accessibility

How to check whether the app is usable with VoiceOver, and how the CI ratchet
keeps it from getting worse.

Background: ticket 32072 — *"Please add support for screenreaders. The tabs at
the bottom, as well as buttons, need to be labeled so that screenreaders can
read them."*

## The tool

`scripts/a11y_audit.py` is a static audit. Python 3.8+, stdlib only, no Xcode,
runs in about a second over the whole repo.

```bash
scripts/a11y_audit.py                  # full report
scripts/a11y_audit.py --summary        # counts per rule
scripts/a11y_audit.py --rule A11Y004   # one rule (repeatable)
scripts/a11y_audit.py --list-rules     # what it checks and how to fix each
scripts/a11y_audit.py --json out.json  # machine-readable
scripts/a11y_audit.py --self-test      # verify the rules themselves still work
```

Scope it while you work on one screen:

```bash
scripts/a11y_audit.py --path "DashWallet/Sources/UI/Payments"
```

## What it checks

| Rule | Sev | What it catches |
|---|---|---|
| A11Y001 | P0 | `UITabBarItem(title: nil)` with no `accessibilityLabel` |
| A11Y002 | P1 | Icon-only `UIBarButtonItem` with no label |
| A11Y003 | P1 | `UIButton` that only ever gets `setImage`, no title, no label |
| A11Y004 | P1 | SwiftUI `Button` whose label is only an image/shape |
| A11Y005 | P1 | `Toggle` with an empty label |
| A11Y006 | P1 | Custom back button replacing UIKit's automatically labeled one |
| A11Y007 | P2 | `.system(size:)` with no `relativeTo:` — ignores Dynamic Type |
| A11Y008 | P0 | `extension Font` shadowing an Apple text style |
| A11Y009 | P1 | `accessibilityLabel` with a bare, unlocalized string |
| A11Y010 | P1 | `accessibilityLabel` key missing from `en.lproj` |
| A11Y011 | P1 | Image-only control in a xib/storyboard with no label |
| A11Y012 | P1 | `.onTapGesture` on a view with no accessibility treatment |

What it does **not** check — these still need a human with VoiceOver on a device:

- whether a label reads *well* (an accurate label can still be a bad one)
- reading order, focus movement, and whether a modal traps focus
- whether state changes are announced (`UIAccessibility.post`) — the app has
  **zero** such announcements today, so nothing tells a blind user that a copy
  succeeded, a PIN was wrong, or a payment went through
- custom controls that need an `.adjustable` trait (sliders, steppers)
- anything that only exists at runtime

A quick VoiceOver spot-check can also mislead you: an unlabeled button does not
go silent, it announces the image asset name — *"icon copy outline"*,
*"diagonal-up-down"*. It sounds like something is there.

## The CI ratchet

`.github/workflows/accessibility.yml` runs on every PR that touches app code.

It fails **only on findings that are not in `scripts/a11y_baseline.json`.** The
existing debt is recorded there, so the check can be adopted today without
fixing everything first — but a PR cannot add a new unlabeled control.

New **P2** findings (Dynamic Type) are printed as advisory and do not fail the
build. Change that with `--fail-on all` once the P2 debt is paid down.

Baseline entries are keyed by a hash of the code snippet, not by line number, so
moving code around or reindenting a file does not create false failures.

### When CI fails on your PR

1. **Fix it.** Almost always one line — `--list-rules` prints the fix for each
   rule.
2. **Or suppress it deliberately**, on the offending line or the one above:

   ```swift
   // a11y-ignore: A11Y004 decorative chevron, the row itself carries the label
   ```

   The rule id and a reason are both required.

3. **Never regenerate the baseline to silence a new finding.** That is what the
   baseline is for, and it is the one thing that makes the ratchet useless.

### Tuning it to our design system

`scripts/a11y_config.json` exists so the rules bend to the codebase rather than
the other way round. Every field is optional:

| Field | Use it for |
|---|---|
| `labeled_wrappers` | our own components that set an accessibility label internally — a view built from one counts as already announced |
| `speaks_for_itself` | components whose API requires a title, so they always read |
| `disabled_rules` | a rule that does not apply to this project at all |
| `advisory_rules` | a rule that should report but never fail CI |
| `exclude_paths` | path prefixes to skip (generated code, debug-only screens) |
| `allowed_font_shadows` | Font tokens we knowingly keep despite shadowing an Apple text style |

Prefer this over scattering `a11y-ignore` comments: a wrapper listed once covers
every call site, and the claim is reviewable in one place. `DashStepper` and
`SegmentedControl` are listed today because both genuinely set their own labels.

**Note on custom fonts and icons.** The audit does not flag either. There are no
bundled font files in the repo and no `Font.custom` / `UIFont(name:)` call sites
— our "custom fonts" are tokens over the system face, and the 159 `dw_font`
helper calls are never flagged because `dw_font(forTextStyle:)` scales
correctly. Custom icons are only ever reported when they are the *entire* label
of a tappable control, which is exactly the case a screen reader cannot resolve.
A11Y008 is not about having our own tokens either: it fires only where a token's
name collides with one of Apple's, and `allowed_font_shadows` turns it off.

### After you fix something

```bash
scripts/a11y_audit.py --write-baseline
```

This banks the progress so the fixed entry can never come back unnoticed. The
`--check` output tells you when there is progress worth banking.

## Where the debt actually is

From the full audit (see ticket 32072), the defects concentrate in a handful of
shared components rather than being spread across screens. Fixing these repairs
an estimated 60–70 screens:

| Component | Defect |
|---|---|
| `UI/Views/Navigation/BaseNavigationController.swift` | replaces UIKit's automatically labeled system Back button with an unlabeled image button |
| `UI/SwiftUI Components/NavigationBar.swift` | back/close/plus/info built from a bare `Icon` — the DashUIKit original *does* set the label; this copy dropped it |
| `UI/SwiftUI Components/MenuItem.swift` | `Toggle(isOn:) { }` with an empty label — every settings switch |
| `UI/SwiftUI Components/DashAmount.swift` | currency symbol is an image, so amounts never say "Dash" |
| `UI/Views/SharedViews/Keyboard/NumberKeyboardButton.swift` | keys are plain `UIView`s with no button trait; the delete key is an image attachment |

`UI/SwiftUI Components/Font+DWStyle.swift` is the Dynamic Type root cause: it
declares an `extension Font` whose members shadow Apple's `body`, `headline`,
`largeTitle`, `title2`, `title3`, `callout`, `footnote` and `caption2`. It
compiles silently and wins inside the app module, so `.font(.body)` — which
looks entirely correct — stops scaling. Any Dynamic Type work starts there.

## Writing accessible UI here

`UI/SwiftUI Components/DashStepper.swift` is the reference: it sets a label, a
value, a hint, and custom actions. Copy its shape.

```swift
Button(action: onClose) {
    Icon(name: .custom("icon_close"))
}
.accessibilityLabel(Text(NSLocalizedString("Close", comment: "Accessibility")))
```

- A control with visible text needs nothing — VoiceOver reads the title.
- An icon-only control always needs `.accessibilityLabel`.
- `accessibilityIdentifier` is for XCUITest and is **never** spoken. It is not a
  substitute for a label.
- A composite row (icon + title + value + chevron) should be one element:
  `.accessibilityElement(children: .combine)`, or `.ignore` plus an explicit
  label.
- Every label is a user-visible string: wrap it in `NSLocalizedString` and let it
  reach Transifex, or it ships English-only across 43 locales.
