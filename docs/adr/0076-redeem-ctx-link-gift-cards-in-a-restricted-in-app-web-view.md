# 0076 — Redeem CTX link gift cards in a restricted in-app web view, with the system browser as the fallback

- **Status:** Proposed
- **Date:** 2026-11-27
- **Deciders:** AshFrancis (author)

## Context

Some DashSpend merchants deliver a gift card as a redeem link instead of a card number. For a CTX
order the link points at the CTX API (`/gift-cards/<id>/redeem`), which redirects to the supplier's
claim page. Some claim pages ask for a challenge code that CTX returns with the order, so the user
needs the code while the page is open. Until now the wallet hid these merchants.

The claim page and everything it loads belong to the supplier and to third parties. The wallet does
not control that content and cannot review it.

## Decision drivers

- The challenge code stays visible while the user fills in the claim page.
- A claim page gets nothing from the wallet except the link the user chose to open.
- The wallet promises only restrictions it can enforce, and says which ones it cannot.
- A claim page and its challenge code are not left open on an unattended or unlocked device.
- No list of supplier hosts to maintain.

## Considered options

1. **System browser for every link** (`UIApplication.open`). The browser's own protections apply and
   the wallet hosts no web content. The user has to copy the code, leave the wallet, and switch back
   if the code is lost from the pasteboard.
2. **`SFSafariViewController`.** Safari's protections apply and the page runs outside the app's
   process. The wallet cannot place its own content above the page: the controller is presented
   whole, and App Store review rules forbid hiding or covering it. The wallet also cannot see or
   restrict navigation, or close the page on its own lock rules, beyond dismissing the controller.
3. **`WKWebView` owned by the wallet, restricted, with the system browser as the fallback.** The code
   sits above the page. The wallet becomes responsible for navigation, permission prompts, dialogs
   and the lock lifecycle of third-party pages.

## Decision outcome

**Chosen:** option 3, for CTX redeem links only, on iOS 18.4 and later; every other case uses the
system browser. It is the only option that keeps the challenge code above the page.

### Trust boundary

Everything inside the web view is untrusted. The wallet gives the page one thing: the redeem link.
There is no script bridge and no message handler, the wallet never types the challenge code into
the page, and the page cannot read or draw the wallet's header. The wallet's own area shows the
merchant name, the host of the top-level page, a caution line and the challenge code.

### What opens in the web view

Only a link that is `https`, on the host of the configured CTX API, on the default port, without
user info, whose path is `/gift-cards/<id>/redeem`, and that Foundation writes back unchanged
(`RedeemLinkPolicy.inAppURL`). The check runs before the screen is shown and again on the first
request WebKit is about to make.

### Restrictions enforced natively

These use public WebKit configuration and delegate calls, so page script cannot undo them.

| Restriction | How | Needs |
|---|---|---|
| Top-level navigation is `https` only; a frame may also be `about:blank` or `about:srcdoc` | navigation action policy, checked again on commit | iOS 18.0 |
| No other scheme is opened or passed to another app (`tel:`, `mailto:`, an app's own scheme) | navigation action policy; the wallet never calls `UIApplication.open` for a page's link | iOS 18.0 |
| No downloads | `shouldPerformDownload`, a MIME type WebKit cannot show, or `Content-Disposition: attachment` cancels the load | iOS 18.0 |
| No new windows | `createWebViewWith` returns nil; an allowed target loads in the same view | iOS 18.0 |
| No camera or microphone capture | `requestMediaCapturePermissionFor` answers deny | iOS 18.0 |
| No device orientation or motion access | `requestDeviceOrientationAndMotionPermissionFor` answers deny | iOS 18.0 |
| No file upload panel (camera, photo library, files) | `runOpenPanelWith` answers nil | iOS 18.4 |
| Script dialogs are the wallet's own, titled with the asking frame's host, at most three per touch; `prompt()` is refused | JavaScript panel delegate calls | iOS 18.0 |
| An invalid server certificate ends the load | default challenge handling | iOS 18.0 |
| Cookies and site storage do not outlive the screen and are not shared with Safari | a new non-persistent data store for every load | iOS 18.0 |

The deployment target is iOS 18.0. The upload panel cannot be refused on 18.0 to 18.3, so on those
versions the web view is not used.

### Limits that are best effort

- **Location.** WebKit has no public delegate call to refuse a page's location request. The wallet
  replaces the page's geolocation functions with a user script that reports "denied". WebKit does
  not run user scripts in a frame's initial empty document (observed on iOS 18.6), so a page can
  still reach WebKit's own location prompt. A position is given only if the user allows it there.
- **The host shown is the top-level page's.** Frames from any `https` origin are allowed, because
  claim pages embed third-party captchas and claim forms and the wallet keeps no list of them. A
  form inside a frame can belong to a different site than the host shown. The host is shown whole;
  the app ships no public-suffix list to reduce it to the registrable domain.
- **Whether a navigation came from a touch.** WebKit reports a script's click as a link activation,
  so the wallet does not treat any navigation as the user's choice to leave the app.
- **Universal links.** An allowed `https` link that the user taps may be one that another installed
  app claims, and iOS may open it there. Public WebKit API has no call to prevent that.

### Lifecycle

- While the app is inactive a cover hides the whole screen, so the app switcher snapshot shows
  neither the page nor the code. A showing dialog or notice is taken down at the same moment.
- The screen closes when the app enters the background: a device lock, a switch to another app, or
  "Open in browser". It also closes when the wallet's lock screen is showing as the app becomes
  active. A system alert, Control Centre or the app switcher alone leave the session open behind
  the cover.
- Closing discards the web view and its data store. Opening the card again starts from the redeem
  link.
- A failed load shows an error state with "Try again" and "Open in browser" in two cases: no page
  has committed yet, or the first navigation (the one the screen started from the redeem link)
  fails after it committed. A cancellation of that committed first navigation is not a failure;
  WebKit reports one when the next navigation replaces the load or a policy decision stops it.
- Once a page has committed, a later navigation that fails leaves the committed page in place, with
  what the user typed into it. This holds even when that page never finished loading, for example
  because one of its frames or resources hangs. "Try again" starts over and applies the same rule
  to the new first navigation.
- A terminated web process always shows the error state.

### When the system browser is used

- The link is not a CTX redeem link (for example a supplier's own claim link).
- The device runs iOS below 18.4.
- The user taps "Open in browser", in the header or in the error state.

The system browser gets any `http` or `https` link with a plainly written host; on the CTX domain,
where the link carries a token, only an `https` link that is opened unchanged
(`RedeemLinkPolicy.externalURL`). A link that fails both checks is not opened.

## Consequences

**Positive**
- The challenge code is in view while the user completes the claim.
- Merchants that deliver links can be listed.
- Site data from a claim does not persist in the wallet.

**Negative**
- The wallet owns a browser surface: each WebKit release can add a capability that needs a new
  refusal here.
- A page can still raise WebKit's location prompt.
- A claim that needs the user to leave the wallet (a code sent by email, a password manager app)
  restarts from the redeem link on return.
- Claim pages that rely on a file upload, a download, a contact link or a pop-up window do not work
  in the web view; the user has to use "Open in browser".
- Safari extensions and content blockers do not apply to the web view.

**Neutral**
- Users on iOS 18.0 to 18.3 keep the system-browser flow, with the code on the gift card sheet.
- If WebKit gains a public call to refuse location requests, the user script is replaced by it.

## Links

- Code: `GiftCardRedeemWebViewModel`, `GiftCardRedeemWebScreen`, `RedeemLinkPolicy`,
  `GiftCardDetailsView.redeem`
- Tests: `RedeemLinkPolicyTests`, `GiftCardLinkRulesTests`
- PR: #1541
