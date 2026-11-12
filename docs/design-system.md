---
status: Living
tool: figma
figma_file: "https://www.figma.com/design/ynpbQC7Cq63tSqX6mMUQsV/Untitled?node-id=27-494"
pen_file: ""
updated_at: "2026-11-05"
---

# Design system — Dash Wallet iOS

> The project's **design canon**, produced once per repo by `design-system` and read by
> `ux-flows` / `screens` / `implement` / `review`. Committed — the tool choice and the inventory
> are team-wide, not per-developer. There is no `architecture-map.md` yet; the code-side facts
> below come from a scan of this repo and of DashUIKit. Refresh via `/sdd:design-system` when the
> foundation changes.

**Anchor convention.** `UIK:` = `https://github.com/dashpay/DashUIKit` at `master` `4494a8b`,
path relative to `Sources/DashUIKit/`. Plain paths are in this repo. Figma nodes are ids in
`figma_file`.

**Pin lag.** The app pins DashUIKit `master` at `2b15ef7`
(`DashWallet.xcworkspace/xcshareddata/swiftpm/Package.resolved:10`). `SegmentedControl`,
`FilterBar`, `NavigationBarCircle*`, `List1View` / `List8View`, `VotePill` and
`MenuViewModifier` exist on DashUIKit `master` only — a feature that uses them bumps the pin
first.

## Platform posture

- **Posture:** mobile-first — Dash Wallet is an iPhone app; screens are drawn at iPhone width.
- **Breakpoints / device classes:** iPhone only, 420-pt frames in Figma (e.g. node `60:203`);
  DashUIKit targets iOS 18 (`UIK: ../../Package.swift:8`). iPad is not a design target.

## Design tool

- **Tool:** figma — the team's screens and the DashUIKit components live in Figma; the Figma
  MCP is available to the pipeline.
- **Library location:** `figma_file` (frame area `27:494`) is the working canvas: new screens
  are drawn there from instances of the DashUIKit Figma library. Reference screens:
  `60:203` (Refund address), `71:195` (Internal transfer), `80:206` (Sheet),
  `81:284` (Sheet "Voting / Filters"). The code side of the library is the DashUIKit package.

## Token source

Tokens come **only from DashUIKit**. A screen never re-declares a color or a text style inline
and never uses the legacy app tokens (`Color+DWStyle.swift`, `Font+DWStyle.swift`) for new UI.

- **Colors:** DashUIKit `Color.dash.*` — `UIK: Foundation/Color+DashUI.swift:21` (`DashColors`
  `:24`, e.g. `primaryText` `:28`, `primaryBackground` `:38`); values in
  `UIK: Resources/Media.xcassets/Colors/`, light + dark per colorset.
- **Typography:** DashUIKit `DashTextStyle` — `UIK: Foundation/DashTextStyle.swift:25`
  (`largeTitle` 34/41 `:43` … `caption2` 11/13 `:58`), applied with `.dashFont(_:)` `:77`;
  `Font.dash.*` (`UIK: Foundation/Font+DashUI.swift:24`) when only a `Font` is needed. Fixed
  sizes — no Dynamic Type.
- **Spacing / sizing / radius:** no DashUIKit scale. Component-owned values stay inside the
  component (e.g. `DashButtonSize` paddings and radii, `UIK: Button/DashButton.swift:20`).
  Screen-level spacing and radii are feature-scoped constants in this repo, declared in the
  feature's own UI folder; the only app-wide globals are `stackSpacing` 15 and `radius` 12
  (`DashWallet/Sources/UI/Style/Style.swift:20`, `:21`).

## Component inventory

New screens compose **DashUIKit** components. The app's own same-named SwiftUI components
(`DashButton`, `MenuItem`, `SegmentedControl` in `DashWallet/Sources/UI/SwiftUI Components/`)
are legacy — qualify `DashUIKit.` where names clash.

| Component | Source (`file:line` / node / URL) | States it supports | Notes |
|---|---|---|---|
| DashButton | `UIK: Button/DashButton.swift:125`; Figma `60:214`, `I80:206;2554:977;80:199` | enabled / disabled / loading | sizes `:21`, 12 styles `:70`; leading/trailing icon |
| NavigationBar | `UIK: Components/NavigationBar.swift:20`; Figma `60:211`, `81:286` | back / close / custom slots | elements enum `:88` |
| NavigationBarCircleButton / Icon / Menu | `UIK: Components/NavigationBarCircleButton.swift:26`, `NavigationBarCircleIcon.swift:30`, `NavigationBarCircleMenu.swift:22` | default / disabled | master only (pin lag) |
| BottomSheet | `UIK: Components/BottomSheet/BottomSheet.swift:7`; Figma `80:206`, `81:284` | back / close / dismissal locked | grabber Figma `81:404` |
| SheetFeature | `UIK: Components/BottomSheet/SheetFeature.swift:30`; Figma `I80:206;2554:978;80:201` | default | icon + title + text row inside a sheet |
| TopIntroView | `UIK: Components/TopIntro/TopIntroView.swift:23`; Figma `60:206` | default / with button | screen header block |
| MenuItem | `UIK: Components/MenuItem.swift:49`; Figma `71:215`, `81:301` | accessories `:23` (toggle / text / button / balance / selection) | list row |
| MenuViewModifier | `UIK: ViewModifiers/MenuViewModifier.swift:20`; Figma `71:212` | default | grouped-list container; master only |
| List1View / List8View | `UIK: Table List/List1View.swift:20`, `Table List/List8View.swift:35` | default | table rows; master only |
| RadioButtonRow | `UIK: Components/RadioButtonRow.swift:30`; Figma `I81:301;8589:107;81:296` | selected / not selected | |
| SimpleSelect | `UIK: Components/SimpleSelect.swift:32` | selected / not selected | |
| SegmentedControl | `UIK: Components/SegmentedControl.swift:67`; Figma `71:208` | selected / not selected | master only (pin lag) |
| FilterBar | `UIK: Components/FilterBar.swift:50` | default | master only |
| DashSwitch / SwitchView | `UIK: Components/DashSwitch.swift:23`, `Components/Switch/SwitchView.swift:18` | on / off / disabled | |
| SearchBar | `UIK: Components/SearchBar.swift:22` | empty / entered | |
| AddressFieldView | `UIK: Components/AddressFieldView.swift:35`; Figma `60:207` | empty / entered / error | the only text-entry field in DashUIKit |
| EnterAmountView | `UIK: Components/EnterAmount/EnterAmountView.swift:32` | styles `:23` | with `NumericKeyboardView` `Components/NumericKeyboardView.swift:123` |
| DashAmount | `UIK: Components/DashAmount.swift:61` | sign `:22` / format `:33` | Dash/fiat amount |
| DashBalanceView | `UIK: Components/EnterAmount/DashBalanceView.swift:25` | shown / hidden | |
| ConverterCard | `UIK: Components/ConverterCard/ConverterCard.swift:30` | default | |
| CoinSelector | `UIK: Components/CoinSelector.swift:33` | trailing variants `:19` | |
| TransactionView | `UIK: Components/Transaction/TransactionView.swift:29` | default | transaction row |
| Criteria | `UIK: Components/Criteria.swift:107` | criterion states `:39` | validation checklist |
| SystemMessageView | `UIK: Components/SystemMessageView.swift:20`; Figma `60:208` | with / without buttons, closable | inline notice |
| ModalDialog | `UIK: Components/ModalDialog.swift:23`; Figma `Dialogue` (`110:3283` two buttons, `110:2968` one) | one / two buttons, destructive role, no icon, long text scrolls | dialog card the host presents over a dim; master only |
| Toast | `UIK: Components/Toast.swift:53` | styles `:35` (warning / info / error / success / copied / loading / noInternet) | |
| Error / Loading / Success illustrations | `UIK: Components/Illustrations/ErrorIllustration.swift:20`, `LoadingIllustration.swift:25`, `SuccessIllustration.swift:20` | — | result screens |
| LoadingSpinner | `UIK: Components/Illustrations/LoadingIllustration.swift:54` | — | |
| Icons | `UIK: Foundation/Icon_DashUI.swift:46` (`DashIcon`), `Foundation/Image+DashUI.swift:25` (`DashIconSource`) | — | plus `CheckmarkIcon` / `ChevronIcon` / `InfoRoundIcon` / `XmarkIcon` in `Components/Icons/` |
| VotePill | `UIK: Components/VotePill.swift:42` | — | master only |

### Gaps

| Gap | Decision | Interim |
|---|---|---|
| Modal dialog | **Closed:** DashUIKit `ModalDialog` (dashpay/DashUIKit#60). | the app's `LegacyModalDialog` (`DashWallet/Sources/UI/SwiftUI Components/Dialogs/ModalDialog.swift:23`) stays for existing screens; moving them is dashpay/dashwallet-ios#1355 |
| Stepper | **Add to DashUIKit.** Colors exist (`UIK: Foundation/Color+DashUI.swift:161`, `stepper*`); the view does not. | — |
| Generic text field | Open — no screen needs it yet. Decide when one does. | app's `DashWallet/Sources/UI/SwiftUI Components/TextInput.swift:21` |
| Empty state | Feature-scoped in this repo, composed from DashUIKit parts (illustration + text + `DashButton`). | — |
| Spacing / radius scale | Feature-scoped constants in this repo (see Token source). | — |

## Interaction & writing conventions

- **Errors:** transient failures → DashUIKit `Toast` (`.error` / `.noInternet`); a persistent
  condition on a screen → `SystemMessageView`; a terminal failure → result screen with
  `ErrorIllustration`.
- **Empty states:** feature-scoped: illustration + one line of text + optional `DashButton`; no
  shared component.
- **Loading:** `DashButton(isLoading:)` for an action in flight; `LoadingSpinner` /
  `LoadingIllustration` for a whole screen or sheet.
- **Validation:** inline on the field (`AddressFieldView` error state) or a `Criteria` checklist;
  the primary `DashButton` stays disabled until the input is valid.
- **Sheets:** DashUIKit `BottomSheet` with grabber; actions sit in the bottom content area.
- **Microcopy tone:** short, plain, sentence case; every string through `NSLocalizedString`;
  icon-only controls carry an `accessibilityLabel` (`ACCESSIBILITY.md`).
