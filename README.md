# DashUIKit protected-sheet migration evidence

This evidence compares the exact stacked base of the protected-sheet migration with its
full implementation head.

| Role | Dash Wallet revision | DashUIKit revision | Simulator |
| --- | --- | --- | --- |
| Before — exact base | `b5273c479814e10966ff0c3903174ad158f2e819` | `5b373b141054438e94903af52b9ec324f1efbdb2` | DashUIKit PR4 Before b5273c479 (`1CC0EAEE-F9FE-436E-803D-2ACF6F2C4480`) |
| After — full head | `a0e4c38a260a7706c8fac504929b52c235ba3670` | `e8d92434bfc28fbf933b896cd40a01dd61835b5f` | DashUIKit PR4 After a0e4c38a2 (`A25BCE13-1653-4D7D-98E8-67486B81F20D`) |

Both devices are clones of the same shut-down DashUIKit PR2 wallet fixture
(`0F16A692-078C-4EAC-B806-A103F6F8F73F`), run iOS 26.5, and use bundle identifier
`org.dashfoundation.dash`. Each revision was built independently with normal Simulator
signing and separate DerivedData. The app built, installed, launched, and remained alive on
both devices.

The two testnet transfers use the same transparent-to-shielded route. The idle pair uses
0.1 tDASH; the fiat quote changed by $0.02 between capture times. The protected pair uses
0.02 tDASH and captures the same locking phase. These transactions share the same testnet
wallet and therefore become visible to both clones after broadcast.

## Idle confirmation

The head replaces the wallet-owned grabber/title shell with the shared DashUIKit header and
its close affordance while preserving the confirmation content and host-owned cancellation.

| Before — exact base | After — full head |
| --- | --- |
| ![Before idle confirmation](comparison/before/internal-transfer-idle.png) | ![After idle confirmation](comparison/after/internal-transfer-idle.png) |

## Protected locking phase

Both revisions prevent swipe dismissal during the operation. The head routes that protection
through DashUIKit and visibly disables the standardized close control at the same time. During
capture, accessibility reported the head's `Close` button as disabled; the base custom sheet
has no close control.

| Before — exact base | After — full head |
| --- | --- |
| ![Before protected transfer](comparison/before/internal-transfer-protected.png) | ![After protected transfer](comparison/after/internal-transfer-protected.png) |

The same API wiring is compiled into send confirmation, shielded recovery, CoinJoin move
funds, evonode withdrawal, and username marketplace actions. DashUIKit's focused tests in
PR 14 cover disabled/default/custom close routing; this wallet evidence demonstrates the
representative host integration.

## Files

All images are unmodified 1206×2622 PNG screenshots inspected at original resolution.

| File | SHA-256 |
| --- | --- |
| `comparison/before/internal-transfer-idle.png` | `f9ecfacf02c799ac4fa16027979a5985f08f60215da2e3c0830ee2c7183de2ec` |
| `comparison/after/internal-transfer-idle.png` | `0072287cd58604c87e8ba8c5014ff599f02bd53e692a9ca87cd4a2449f7bfc24` |
| `comparison/before/internal-transfer-protected.png` | `906a57dfe8564b1faddb2d14a6ffc44a68271fab11c67bc3cd905698a53504e7` |
| `comparison/after/internal-transfer-protected.png` | `bf18d5233a47f838dc147dfc32b25d3a9e6dc5cbf87a0c159911fcf42cd2c943` |
