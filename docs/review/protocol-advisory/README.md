# Protocol advisory review captures

Captured on 2026-10-27 in an isolated iPhone 17 simulator using the actual HomeView and SDKIdentityProfileSheet. The temporary Debug fixture supplied verified protocol 16, effective 15 and maximum 15; Home had no wallet and Profile used a synthetic identity. No user wallet data is included.

The application changes are in commit 91860b30cb35867cdbf5783e99bf8133c7b32c8e. The before captures reproduce the Release advisory copy from 95ffa0d4856a4f531e6dd4444ab0e0c22faf8374 in the same views; they are not captures of an installed historical distribution binary. The after captures use the current copy. The actual TestFlight workflow archives Release, so this matrix applies to the App Store and TestFlight guidance. The unused historical Testflight-configuration branch is not represented.

Each view has before/after captures in light and dark appearance. Screenshots demonstrate layout and copy, not live proof verification, unsupported-network behavior or a signed distribution build. Temporary fixture source was restored before committing and is not part of the application change.
