
# Developer Notes

## Pre Requirements

- Xcode 10.2
- Dependency manager [CocoaPods](https://cocoapods.org). Installation: `gem install cocoapods`
- Localized files helper tool (optional) [BartyCrouch](https://github.com/Flinesoft/BartyCrouch). Installation: `brew install bartycrouch`

## Generating screenshots for AppStore

 1. Install [fastlane](fastlane.tools) by running `brew cask install fastlane`
 2. Uncomment `#define SNAPSHOT 1` in **DashWallet-Prefix.pch** file
 3. Run `fastlane snapshot` (ETA ~1.5 hours on MBP 2017 i7 2.8 Ghz, 16 RAM) 
 4. Upload screenshots by running `fastlane deliver`

## Managing localized files

### Requirements

- [Transifex client](https://docs.transifex.com/client/installing-the-client)

#### Updating strings on transifex

1.  Build project (BartyCrouch build phase will add/update/remove localized strings)
2.  Run  `tx push -s`  to update base localization (en) strings on transifex

#### Getting translations from transifex

1.  Just run  `tx pull`
