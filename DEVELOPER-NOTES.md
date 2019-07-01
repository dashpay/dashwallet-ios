
# Developer Notes

## Pre Requirements

- Xcode 10.2
- Dependency manager [CocoaPods](https://cocoapods.org). Installation: `gem install cocoapods`
- Localized files helper tool (optional) [BartyCrouch](https://github.com/Flinesoft/BartyCrouch). Installation: `brew install bartycrouch`

## Generating screenshots for AppStore

 1. Install [fastlane](fastlane.tools) by running `brew cask install fastlane`
 2. Uncomment `#define SNAPSHOT 1` in **DashWallet-Prefix.pch** file
 3. Run `fastlane snapshot` (ETA ~1.5 hours on MBP 2017 i7 2.8 Ghz, 16 RAM) 
 4. Upload screenshots by running `fastlane deliver --skip_binary_upload --skip_metadata --skip_app_version_update`

## Managing localized files

### Requirements

- [Transifex client](https://docs.transifex.com/client/installing-the-client)

#### Updating strings on transifex

1.  Build project (BartyCrouch build phase will add/update/remove localized strings)
2.  Run  `tx push -s`  to update base localization (en) strings on transifex

#### Getting translations from transifex

1.  Just run  `tx pull`

## In-house crash reporting

DashWallet uses fork of [PLCrashReporter](https://github.com/podkovyrin/plcrashreporter) to allow users to manually send crash reports if they decided to share it with us.

#### Decoding crash reports

Download or clone PLCrashReporter and build **plcrashutil** target (archiving with release configuration might be a good idea).

Run the following command to convert plcrash to regular crash: `./plcrashutil convert --format=ios crash_report.plcrash > report.crash`

Symbolicate resulting crash report with **symbolicatecrash** tool (`/Applications/Xcode.app/Contents/SharedFrameworks/DVTFoundation.framework/Versions/A/Resources/symbolicatecrash`):

1. Set needed env `export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"`
2. Place .crash, .app and .dSYM in the same directory
3. Run `symbolicatecrash report.crash > symbolicated.crash`

See also:

[Technical Note TN2151 Understanding and Analyzing Application Crash Reports](https://developer.apple.com/library/archive/technotes/tn2151/_index.html#//apple_ref/doc/uid/DTS40008184)

[Technical Q&A QA1765 How to Match a Crash Report to a Build](https://developer.apple.com/library/archive/qa/qa1765/_index.html#//apple_ref/doc/uid/DTS40012196)

[Symbolicating Your iOS Crash Reports](https://possiblemobile.com/2015/03/symbolicating-your-ios-crash-reports/)
