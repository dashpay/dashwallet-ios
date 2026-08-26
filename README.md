# DashUIKit bottom-sheet consolidation visual evidence

This orphan branch stores the full-resolution iOS Simulator evidence for the
Dash Wallet bottom-sheet foundation migration to `DashUIKit.BottomSheet`.

## Provenance

| State | Exact revision | Simulator |
| --- | --- | --- |
| Before | `be25f358d9f606103d4da956c1310d756d436070` | DashUIKit PR1 Before be25f358d (`3DD208A7-27A7-484B-B5A1-E71DCFE88EA3`) |
| After | `ab566189742eb386516e9fc4c2d9e940d577a749` | DashUIKit PR1 After da6475453 (`9462A942-59F2-4962-AF3F-EE911A9A05D9`) |

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
| Transaction filter | `1aab0333ead05e0617975712d0c9fbbe532421b776865521fef03a156a05e71f` | `4580c19a9aa8d08743b8712d2a0fe994c5612070bfe04b26c74ff09c1d67c0dc` |
| Transaction detail | `761c3ae031a462b4819b76d0d9d4184bc3da6a19ebc2d576ccd5f3764fe3239b` | `480122108626c4f8cad5345ba7739861eb09f6de01d3f9c5e2e0f4c60f4aeb33` |

## Transaction filter

| Before — exact base | After — full head |
| --- | --- |
| ![Before transaction filter](comparison/before/transaction-filter.png) | ![After transaction filter](comparison/after/transaction-filter.png) |

## Transaction detail

| Before — exact base | After — full head |
| --- | --- |
| ![Before transaction detail](comparison/before/transaction-detail.png) | ![After transaction detail](comparison/after/transaction-detail.png) |
