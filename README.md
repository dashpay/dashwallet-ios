# Dash Wallet

[![Build Status](https://github.com/dashpay/dashwallet-ios/actions/workflows/semantic-pull-request.yml/badge.svg)](https://github.com/dashpay/dashwallet-ios/actions) [![License](https://img.shields.io/badge/license-MIT-green)](https://github.com/dashevo/dashwallet-ios/blob/master/LICENSE) [![Release](https://img.shields.io/github/v/release/dashpay/dashwallet-ios)](https://github.com/dashpay/dashwallet-ios/releases) [![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20watchOS-blue)](https://github.com/dashevo/dashwallet-ios)

<p align="center" >
<img src="https://docs.dash.org/en/stable/_images/dash_logo.png" alt="Dash Wallet logo" title="Dash Wallet" width="300">
</p>

*Dash Wallet* (breadwallet fork) is a real standalone [Dash](https://dash.org) client. There is no server to get hacked or go down, so you can always access your money.
Using [SPV](https://en.bitcoin.it/wiki/Thin_Client_Security#Header-Only_Clients) mode, *Dash Wallet* connects directly to the Dash network with the fast performance you need on a mobile device.
*Dash Wallet* is designed to protect you from malware, browser security holes, even physical theft. With AES hardware encryption, app sandboxing,
keychain and code signatures, *Dash Wallet* represents a significant security advantage over web and desktop wallets, and other mobile platforms.
Simplicity is *Dash Wallet*’s core design principle. A simple backup phrase is all you need to restore your wallet on another device if yours is ever lost or broken.
Because *Dash Wallet* is [deterministic](https://dashpay.atlassian.net/wiki/display/DOC/Whitepaper), your balance and transaction history can be recovered from just your backup phrase.

## Features

- ["simplified payment verification"](https://dashpay.atlassian.net/wiki/display/DOC/Official+Documentation) for fast mobile performance
- no server to get hacked or go down
- single backup phrase that works forever
- private keys never leave your device
- import [password protected](https://dashpay.atlassian.net/wiki/display/DOC/Official+Documentation) paper wallets
- [“payment protocol”](https://dashpay.atlassian.net/wiki/display/DOC/Official+Documentation) payee identity certification
- [Uphold](https://uphold.com) integration

## Download

[![Download on the AppStore](https://linkmaker.itunes.apple.com/en-gb/badge-lrg.svg?releaseDate=2017-07-19&kind=iossoftware&bubble=ios_apps)](https://apps.apple.com/app/dash-wallet/id1206647026?mt=8)

## Getting Started

To run *Dash Wallet* iOS app on your device or simulator clone the repo and make sure you installed needed [Requirements](#Requirements).
Then run `pod install` in the cloned directory.
Open `DashWallet.xcworkspace` in Xcode and run the project.

## Requirements

- Xcode 11
- Dependency manager [CocoaPods](https://cocoapods.org). Install via `gem install cocoapods`

### DashPay Requirements

Currently, DashPay wallet is under active development so it requires a few additional steps to make it work.

1. Clone [DashSync](https://github.com/dashevo/dashsync-iOS) and [dapi-grpc](https://github.com/dashevo/dapi-grpc) repositories:  
`git clone https://github.com/dashevo/dashsync-iOS.git DashSync`  
`git clone https://github.com/dashevo/dapi-grpc.git dapi-grpc`

To simplify developing process we use local podspec dependencies and it's important to preserve the following folder structure:
```
../DashSync/
../dapi-grpc/
../dashwallet-ios/
```

2. Install protobuf and grpc:
`brew install protobuf grpc`

3. Install last version of rust:
`curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`

4. Install cmake and make sure it is located in one of the following folders:
`${PLATFORM_PATH}/Developer/usr/bin, ${DEVELOPER}/usr/bin:/usr/local/bin, /usr/bin, /bin, /usr/sbin, /sbin, /opt/homebrew/bin`

5. Run `pod install` in the wallet directory.

### Optional Requirements

#### Objective-C Related
- Formatting tools: [clang-format](https://clang.llvm.org/docs/ClangFormat.html). Install via `brew install clang-format`.

#### Swift Related
- [SwiftFormat](https://github.com/nicklockwood/SwiftFormat). Install via `brew install swiftformat`. 
- [SwiftLint](https://github.com/realm/SwiftLint).  Install via `brew install swiftlint`.

#### Localization

- Localized files helper tool [BartyCrouch](https://github.com/Flinesoft/BartyCrouch). Install via `brew install bartycrouch`.

## Contribution Guidelines

We use Objective-C for developing iOS App and underlying [DashSync](https://github.com/dashevo/dashsync-iOS) library and Swift for the Watch App.

General information on developing conventions you can find at [Apple Developer Portal](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/ProgrammingWithObjectiveC/Conventions/Conventions.html).
For more specific Objective-C guidelines we stick with [NYTimes Objective-C Style Guide](https://github.com/nytimes/objective-c-style-guide).

Our code style is enforced by [clang-format](#Objective-C-Related) and [SwiftFormat / SwiftLint](#Swift-Related).

## Documentation

Official Dash documentation is available [here](https://docs.dash.org).

## URL Schemes

For more information follow this [documentation page](https://docs.dash.org/en/stable/wallets/ios/advanced-functions.html#url-scheme).

## WARNING

Installation on jailbroken devices is strongly discouraged.

Any jailbreak app can grant itself access to every other app's keychain data and rob you by self-signing as described [here](http://www.saurik.com/id/8) and including `<key>application-identifier</key><string>*</string>` in its .entitlements file.

## License

*Dash Wallet* is available under the MIT license. See the LICENSE file for more info.
