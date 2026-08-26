# DashUIKit sheet-content migration visual evidence

This orphan branch stores the full-resolution iOS Simulator evidence for the
second Dash Wallet bottom-sheet migration PR. It covers the dismiss-safe sheet
content moved onto `DashUIKit.BottomSheet`.

## Provenance

| State | Exact revision | Simulator |
| --- | --- | --- |
| Before | `da64754531a36be79756f03140380be540056459` | DashUIKit PR2 Before da6475453 (`623AEDFC-3715-417F-9C20-378F1ABFE20A`) |
| After | `b5273c479814e10966ff0c3903174ad158f2e819` | DashUIKit PR2 After b5273c479 (`0F16A692-078C-4EAC-B806-A103F6F8F73F`) |

Both simulators were cloned while shut down from the same configured
`PR 1067 After a2b9f1f` fixture
(`46345DF3-5747-4886-9539-18206110B245`). Each exact revision was built in an
independent worktree with separate DerivedData, installed on its corresponding
clone, launched successfully, and verified live before navigation. The captures
are unedited `simctl io screenshot` PNGs from an iPhone 17 Pro on iOS 26.5 at
1206 × 2622 pixels.

## File integrity

| Surface | Before SHA-256 | After SHA-256 |
| --- | --- | --- |
| Balance info | `e935d44a60d1cc0c4e24f27f3596fa8a7d366bc7d4d3d13a4ff96c9374433fcf` | `b609ff32600c5a3252ebd694c0a7f67f360b0ee8a201e49dee7d1d7e63e5c954` |
| CSV export | `ca32dea8407750ef5baea5d619158aeda314bab53f2fae02c9c840f75dbd426b` | `f1095d4671b30fa4495b3941fbf509155e0fd2c0508ad7f30cadc930f93197f5` |
| Extended public key | `ed8c08ce8ca52f364f327053fd79c474591f8bc1c1d4fa1f88ddb6208a51e6ce` | `c6b1812bcdbf074728bd2e16dd135d078b26b2eba0d84bfaa5bd5b448dc82894` |
| ZenLedger | `9ad1d1cfa984313101c6a6c8ffb1f994a371441c48ee4f6b12c40dbde9d8773c` | `9194841a578f811a4231f5e4e505e6a0eaf5a170dd3f1bea101aa6a730280cb0` |
| Transfer timing | `69739b99948f4130a1f6c9ee2e2e6e0282ed3741f7fd3685a02d7741cdbdc027` | `8ca87846524577a709c1d5fbd3190853d6318e46673ccc2e71fac0bb4576b87d` |
| Transfer endpoint picker | `a13590ea53fe1ab25243f3df122637294abc2ffd710d6bbb06db20c11a96d0a6` | `e9ebc3fe25a8665872dd7a37bf967353386321978e313a5982ed137924fbee27` |

## Balance info

| Before — exact base | After — full head |
| --- | --- |
| ![Before balance info](comparison/before/balance-info.png) | ![After balance info](comparison/after/balance-info.png) |

## CSV export

| Before — exact base | After — full head |
| --- | --- |
| ![Before CSV export](comparison/before/csv-export.png) | ![After CSV export](comparison/after/csv-export.png) |

## Extended public key

| Before — exact base | After — full head |
| --- | --- |
| ![Before extended public key](comparison/before/extended-public-key.png) | ![After extended public key](comparison/after/extended-public-key.png) |

## ZenLedger

| Before — exact base | After — full head |
| --- | --- |
| ![Before ZenLedger](comparison/before/zenledger.png) | ![After ZenLedger](comparison/after/zenledger.png) |

## Transfer timing

| Before — exact base | After — full head |
| --- | --- |
| ![Before transfer timing](comparison/before/transfer-timing.png) | ![After transfer timing](comparison/after/transfer-timing.png) |

## Transfer endpoint picker

| Before — exact base | After — full head |
| --- | --- |
| ![Before endpoint picker](comparison/before/endpoint-picker.png) | ![After endpoint picker](comparison/after/endpoint-picker.png) |
