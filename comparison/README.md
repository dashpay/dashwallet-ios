# PR 1100 visual evidence

This directory contains before/after screenshots for
[dashpay/dashwallet-ios#1100](https://github.com/dashpay/dashwallet-ios/pull/1100).

| Surface | Before — exact base | After — full PR head | Visible delta |
| --- | --- | --- | --- |
| Create Wallet | `comparison/before/create-wallet.png` | `comparison/after/create-wallet.png` | Adds the optional wallet-name field, placeholder, and default-name guidance above recovery phrase length. |
| Import Wallet | `comparison/before/import-wallet.png` | `comparison/after/import-wallet.png` | Adds the same optional wallet-name field and guidance above recovery phrase entry. |

## Provenance

- Before revision: `c01d56211e0cf13704e75fcb160f99849bd876e8`
- After revision: `a3389374d2b1e5cfb7e3a10d20192a3624f0eb95`
- Bundle identifier: `org.dashfoundation.dash`
- Simulator runtime/device: iOS 26.5, iPhone 16 Pro
- Shared fixture: fresh zero-balance wallet configured once on simulator
  `PR1100 Fixture` (`2BA73F81-DD2A-4971-BA50-6D2C50FFCA4A`), then cloned as
  `PR1100 Before` (`4CC8345A-B447-4876-B616-F207DE655D7D`) and
  `PR1100 After` (`171E323E-BCD0-4B94-AF56-ACD14599EA16`).
- Each revision was built, signed, installed, launched, and checked for process
  liveness independently with separate DerivedData directories.
- The Create Wallet flow generates a new random mnemonic when opened. The
  throwaway mnemonics therefore differ between screenshots; this is unrelated
  to the optional-name UI change and no wallet was funded.
- All images are full-resolution simulator captures at 1206 x 2622 pixels and
  were inspected at original resolution before publication.

## SHA-256

```text
afc6660477e55ce6e812f88d8eb78d55ff251287db476caa59094399e7af841d  comparison/before/create-wallet.png
bee6dd307d836c955424b6c322199119cdffc6ff08be8d6a2a7558fad897016e  comparison/after/create-wallet.png
8218cbaeb96dfc999cd3db1eee6d72773eefddebd4555aa21645800d10b0772d  comparison/before/import-wallet.png
0ae5e4f4fbd4d70a6ee3342b6b1b2f5a71f6bb55ab27d5e0496ebd5cd419e680  comparison/after/import-wallet.png
```
