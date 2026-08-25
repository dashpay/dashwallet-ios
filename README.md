# Pull request 1065 visual evidence

This branch stores the full-resolution simulator evidence for
[`dashpay/dashwallet-ios#1065`](https://github.com/dashpay/dashwallet-ios/pull/1065).

| State | Exact revision | Simulator | SHA-256 |
| --- | --- | --- | --- |
| Before | `53bb20d70f53e981bd0eba27a3185982b7318e33` | Marketplace Sheet Before (`EE3A1FF6-5E2C-4496-9513-F4E8F638CEF2`) | `f5104bf3a9023ceb7907956d3ada6617c53ee0f1464c9985bb6776187982b9de` |
| After | `48d5be0c9d575a6f4fcb118f8fcfa67a5fffa480` | PR 1065 After 48d5be0c9 (`D2569D58-670A-47CC-92CF-7918FCC6656B`) | `f308253da183f85517c9522657ae3f0ed8039a562261b43e56ba4bc43a4a4fe2` |

Both simulators were cloned from the same configured `Compare - Auto Receive`
fixture (`58AE006C-D6D9-4CF4-AF26-56FFAC0CB063`), run on iOS 26.5, and show the
same `helloworld12354` standard registration flow at 1206 × 2622 pixels.

## Before — exact base

![Before — exact base](comparison/before/username-registration-sheet.png)

## After — full PR head

![After — full PR head](comparison/after/username-registration-sheet.png)
