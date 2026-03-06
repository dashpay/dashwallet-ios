# Maya Protocol Integration - iOS Implementation Plan

This document tracks the implementation of Maya Protocol (decentralized crypto exchange) in the iOS Dash Wallet. It serves as the single source of truth for requirements, architecture decisions, and implementation progress.

## Reference Material
- **Android implementation**: https://github.com/dashpay/dash-wallet/compare/master...feature-maya
- **Maya API docs**: https://docs.mayaprotocol.com/dev-docs/mayachain/concepts/connecting-to-thorchain
- **Maya API Swagger**: https://mayanode.mayachain.info/mayachain/doc
- **Figma designs**: https://www.figma.com/design/84tUBQA9DYU1svyQx8tnbk/DashPay---Android
- **Requirements PDF**: See project documentation

---

## API Reference

### Base URLs
- **MayaNode (mainnet)**: `https://mayanode.mayachain.info/mayachain/`
- **Midgard (legacy, pools+prices)**: `https://midgard.mayachain.info/v2/`

### Endpoints
| Endpoint | Base | Purpose |
|----------|------|---------|
| `GET /pools` | Midgard | List pools with USD prices and status |
| `GET /inbound_addresses` | MayaNode | Vault addresses, halted chain status |
| `GET /quote/swap?from_asset=DASH.DASH&to_asset={asset}&amount={sats}&destination={addr}` | MayaNode | Get swap quote with fees and expected output |
| `GET /tx/{txid}` | MayaNode | Track swap transaction status |

### Key API Notes
- All amounts use **1e8 base units** (satoshis), even for ETH (which natively uses 1e18)
- Pool status values: `"available"`, `"staged"`
- Maya asset notation: `CHAIN.SYMBOL` (e.g., `BTC.BTC`, `ETH.USDC-0XA0B8...`)

---

## Current iOS State

### Implemented (merged to master via PR #753)
- Maya service added to `BuySellPortalModel.swift` Service enum
- `MayaPortalViewController.swift` — thin UIKit wrapper for navigation
- `MayaPortalView.swift` — SwiftUI portal with "Convert Dash" placeholder button
- Navigation: Buy & Sell portal → Maya Portal
- SVG assets: `maya.logo`, `portal.maya`, `convert.crypto`

### Not Yet Implemented
- "Convert Dash" button action (currently a no-op)
- All 8 requirements below

---

## Requirements Overview

| # | Feature | Figma Node | Branch | Status |
|---|---------|-----------|--------|--------|
| 1 | Select Destination Coin | 24007-4644 | `feat/maya-select-dest-coin` | Implemented (PR #755) |
| 2 | Enter Destination Address | 24007-6732 | `feat/maya-enter-dest-address` | In Progress |
| 3 | Retrieve Coinbase & Uphold Addresses | 24014-6577 | TBD | Not Started |
| 4 | Validate Destination Address | 24032-36179 | TBD | Not Started |
| 5 | Enter Amount Screen | 24015-8963 | TBD | Not Started |
| 6 | Order Preview Screen | 24021-11223 | TBD | Not Started |
| 7 | Submit Transaction & Error Handling | — | TBD | Not Started |
| 8 | Halted Coin Error | 24007-4644 | TBD | Not Started |

---

## Requirement 1: Select Destination Coin

### User Story
As a user who wants to swap their Dash for another crypto, I would like to be able to select what crypto to buy.

### Acceptance Criteria
- The user should be able to select from any crypto supported on the Maya network
- Coin details should be hard-coded (matching Android); unsupported coins excluded from UI
- Display: coin logo, coin name, short code, fiat price
- Prices converted to user's default fiat currency

### Design Specs (Figma node 24007-4644)

**Screen layout:**
- Navigation bar with back button and "Select coin" title
- Search bar (rounded, grey background, magnifying glass icon)
- Coin list in white card with subtle shadow

**Each coin row:**
- Left: 26x26px logo (6px corner radius) + coin name (14px medium) + ticker (12px regular, grey)
- Right: fiat price (12px regular, grey)

**Halted coin row:**
- 50% opacity + greyscale overlay
- "halted" badge instead of price (grey background, 6px radius)

**Toast notification (bottom):**
- Dark translucent background with warning icon
- "Some coins are not available because of the halted chain"
- Dismissible with X button

### Implementation Plan

#### Files to Create
```
DashWallet/Sources/Models/Maya/
├── MayaCryptoCurrency.swift      # Coin definitions, hardcoded list, asset notation
├── MayaPool.swift                # Pool API response model (asset, price, status)
└── MayaAPIService.swift          # Network layer for Maya endpoints

DashWallet/Sources/UI/Maya/
├── SelectCoinView.swift          # SwiftUI coin picker screen
├── SelectCoinViewModel.swift     # ViewModel: fetch pools, filter, search, fiat conversion
├── CoinRowView.swift             # Reusable coin row component (normal + halted states)
└── SelectCoinHostingController.swift  # Thin UIKit wrapper for navigation
```

#### Step-by-Step

1. **Define coin model** (`MayaCryptoCurrency.swift`)
   - Enum or struct with code, name, maya asset string, chain, icon asset name
   - Static `supportedCoins` list matching Android's `MayaCurrencyList`
   - Filter out DASH.DASH from picker

2. **Create API service** (`MayaAPIService.swift`)
   - Fetch pools from Midgard `GET /v2/pools`
   - Fetch inbound addresses from MayaNode `GET /inbound_addresses`
   - Parse responses into `MayaPool` models

3. **Build ViewModel** (`SelectCoinViewModel.swift`)
   - Fetch pool data on appear
   - Cross-reference pools with hardcoded coin list
   - Filter: only coins in hardcoded list AND pool status == "available"
   - Convert USD prices to user's fiat currency using existing `CurrencyExchanger`
   - Search filtering by name or ticker
   - Track halted status from inbound addresses

4. **Build UI** (`SelectCoinView.swift`, `CoinRowView.swift`)
   - Navigation bar with "Select coin" title
   - Search bar with text binding
   - List of `CoinRowView` items
   - Normal state: logo, name, ticker, price
   - Halted state: greyed out, "halted" badge, selection disabled
   - Toast view at bottom when halted coins exist

5. **Add coin icon assets**
   - Download SVGs from Figma MCP for each coin
   - Clean SVGs for iOS compatibility (no CSS vars, explicit dimensions)
   - Add to `AppAssets.xcassets` with `preserves-vector-representation: true`

6. **Wire up navigation**
   - Connect "Convert Dash" button in `MayaPortalView` to push `SelectCoinHostingController`
   - On coin selection, navigate forward (placeholder for Requirement 2)

---

## Requirement 2: Enter Destination Address

### User Story
As a user who has selected a destination coin, I would like to have easy ways to enter the associated address.

### Acceptance Criteria
- Scan QR code of destination wallet
- Manually type the address
- Paste from clipboard

---

## Requirement 3: Retrieve Coinbase & Uphold Addresses

### User Story
As a user with an exchange account at Uphold or Coinbase, I would like to select a destination address from one of those accounts.

### Acceptance Criteria
- Log into Uphold/Coinbase if not already logged in
- Select address from Coinbase account (Coinbase API: list accounts, get address)
- Select address from Uphold account (Uphold API: card addresses)
- Select address from clipboard if valid

### API References
- Coinbase: https://docs.cloud.coinbase.com/sign-in-with-coinbase/docs/api-accounts#list-accounts
- Uphold: https://docs.uphold.com

---

## Requirement 4: Validate Destination Address

### User Story
As a user who has specified a destination address, I would like to be sure that it is valid.

### Acceptance Criteria
- Validate based on destination coin's address format standards
- Validate when user clicks Continue
- Show error for invalid addresses
- Block navigation to order preview if invalid

---

## Requirement 5: Enter Amount Screen

### User Story
As a user who has selected a destination coin and address, I would like to enter the amount to convert.

### Acceptance Criteria
- Enter amount in fiat, Dash, or destination crypto
- Auto-update other amounts when one changes
- Use Maya pool prices for conversion
- Support "max amount" from wallet balance
- Show destination address and coin icons

---

## Requirement 6: Order Preview Screen

### User Story
As a user who has entered all required information, I would like to confirm the details.

### Acceptance Criteria
- Show Dash and destination crypto amounts with icons
- Show destination address
- Show totals with and without fees
- Show fee breakdown
- Cancel option
- 10-second countdown timer to submit
- Refresh quotes after timeout

---

## Requirement 7: Submit Transaction & Error Handling

### User Story
As a user who has submitted a transaction, I would like to know if it was successful.

### Acceptance Criteria
- Inform user of completion or failure
- Network unavailable handling (same as Coinbase)
- Success → return to home screen
- Failure → return to Maya portal with support link

### Technical Notes
- Transaction construction: VOUT0=vault address, VOUT1=OP_RETURN with swap memo, VOUT2=change
- Memo format from `/quote/swap` response

---

## Requirement 8: Halted Coin Error

### User Story
As a user who wants to swap Dash, I want to know if the chain is halted on the destination coin.

### Acceptance Criteria
- Halted coins shown in error state (greyed out + "halted" badge)
- User cannot proceed with halted coins
- Toast notification explaining unavailability

---

## Hardcoded Coin List

Sourced from Android `MayaCurrencyList`. Only coins in this list AND with pool status `"available"` are shown in the picker.

| Code | Name | Maya Asset | Chain | Address Type |
|------|------|-----------|-------|-------------|
| BTC | Bitcoin | BTC.BTC | BTC | Bech32/Base58 |
| ETH | Ethereum | ETH.ETH | ETH | Ethereum (0x) |
| PEPE | PEPE | ETH.PEPE-0X6982508145454CE325DDBE47A25D4EC3D2311933 | ETH | Ethereum |
| USDC | USD Coin | ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48 | ETH | Ethereum |
| USDT | Tether | ETH.USDT-0XDAC17F958D2EE523A2206206994597C13D831EC7 | ETH | Ethereum |
| WSTETH | Wrapped stETH | ETH.WSTETH-0X7F39C581F595B53C5CB19BD0B3F8DA6C935E2CA0 | ETH | Ethereum |
| ARB | Arbitrum | ARB.ARB-0X912CE59144191C1204E64559FE8253A0E49E6548 | ARB | Ethereum |
| ETH (ARB) | Ethereum (Arbitrum) | ARB.ETH | ARB | Ethereum |
| DAI | Dai | ARB.DAI-0XDA10009CBD5D07DD0CECC66161FC93D7C9000DA1 | ARB | Ethereum |
| GLD | Goldario | ARB.GLD-0XAFD091F140C21770F4E5D53D26B2859AE97555AA | ARB | Ethereum |
| LEO | LEO | ARB.LEO-0X93864D81175095DD93360FFA2A529B8642F76A6E | ARB | Ethereum |
| LINK | ChainLink | ARB.LINK-0XF97F4DF75117A78C1A5A0DBB814AF92458539FB4 | ARB | Ethereum |
| PEPE (ARB) | PEPE (Arbitrum) | ARB.PEPE-0X25D887CE7A35172C62FEBFD67A1856F20FAEBB00 | ARB | Ethereum |
| TGT | THORWallet | ARB.TGT-0X429FED88F10285E61B12BDF00848315FBDFCC341 | ARB | Ethereum |
| USDC (ARB) | USD Coin (Arbitrum) | ARB.USDC-0XAF88D065E77C8CC2239327C5EDB3A432268E5831 | ARB | Ethereum |
| WBTC | Wrapped Bitcoin | ARB.WBTC-0X2F2A2543B76A4166549F7AAB2E75BEF0AEFC5B0F | ARB | Ethereum |
| WSTETH (ARB) | Wrapped stETH (ARB) | ARB.WSTETH-0X5979D7B546E38E414F7E9822514BE443A4800529 | ARB | Ethereum |
| KUJI | Kujira | KUJI.KUJI | KUJI | Bech32 (kujira prefix) |
| RUNE | Rune | THOR.RUNE | THOR | Custom (thor prefix) |

**Notes:**
- DASH.DASH is defined in the system but filtered out of the coin picker (can't swap Dash to Dash).
- USK (KUJI.USK) is listed in some Android references but excluded from the iOS implementation (19 coins total) as it does not have an active Maya pool.

---

## Coin Icon Strategy
- Android loads from: `https://raw.githubusercontent.com/jsupa/crypto-icons/main/icons/{code}.png`
- iOS approach: Bundle SVGs in asset catalog from Figma designs
  - Offline support, consistent rendering, no network dependency
  - Clean SVGs for iOS (no CSS custom properties, explicit pixel dimensions)

## Fiat Price Conversion
- Pool prices from Midgard API are in USD (`assetPriceUSD`)
- Convert to user's fiat using existing iOS `CurrencyExchanger` infrastructure
- Android fallback chain (CurrencyBeacon → FreeCurrency → ExchangeRate) as reference if needed

---

## iOS Architecture Decisions

- **SwiftUI-first** for all new UI (per project CLAUDE.md policy)
- Thin UIKit hosting controllers only for navigation integration
- **MVVM** with `@ObservableObject` ViewModels
- Source directory: `DashWallet/Sources/UI/Maya/`
- Models directory: `DashWallet/Sources/Models/Maya/`
- Networking: Evaluate existing `HTTPClient` or create dedicated `MayaAPIService`

### Navigation Flow
```
Buy & Sell Portal
  → MayaPortalView ("Convert Dash" button)
    → SelectCoinView (coin picker)              ← Req 1
      → EnterDestinationAddressView             ← Req 2 + 3 + 4
        → EnterAmountView                       ← Req 5
          → OrderPreviewView                    ← Req 6
            → TransactionResultView             ← Req 7
```
