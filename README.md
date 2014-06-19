![ƀ](/images/icon.png) breadwallet
----------------------------------

[![download](/images/Download_on_the_App_Store_Badge_US-UK_135x40.png)]
(https://itunes.apple.com/app/breadwallet/id885251393)

An [SPV](https://en.bitcoin.it/wiki/Thin_Client_Security#Header-Only_Clients),
[BIP32](https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki)
deterministic bitcoin wallet for iOS

breadwallet is designed to be the simplest, easiest and most secure bitcoin
wallet for iOS 

breadwallet is the first true bitcoin wallet for iOS, where you hold your
money right on your own device without relying on any third party service 

![screenshot1](/images/screenshot1.jpg)

features:

- open source 
- single backup phrase that works forever 
- private keys never leave your device 
- "simplified payment verification" for fast mobile performance 
- import password protected paper wallets 
- "payment protocol" payee identity certification

![screenshot3](/images/screenshot3.jpg)

breadwallet uses "simplified payment verification" or
[SPV](https://en.bitcoin.it/wiki/Thin_Client_Security#Header-Only_Clients) mode
for fast performance in a mobile environment.

breadwallet is a 
[BIP32](https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki)
"deterministic" wallet, meaning that all the bitcoin addresses
and private keys are generated from a single "seed". If you know the seed, you
can recreate the entire wallet including all balances and transaction history.
This allows for a single convenient backup that will work forever.

The wallet seed is securely stored on the iOS keychain and never leaves your
device. It is never stored on any server. Your private keys are generated from
your seed as needed and then immediately wiped from memory. Additionally, iOS
keychain data persists even if the app is deleted. If you accidentally delete
breadwallet and reinstall it, your wallet will be automatically recreated from
the seed stored on the keychain. (Be sure to do a factory reset if you sell or
give away your device!)

The seed is also encoded into a non-sense english phrase, which is your
"wallet backup phrase". Never let anyone see your backup phrase or they will
have access to your wallet. Write it down and store it in a safe place. In the
event your device is damaged or lost you can restore your wallet on a new device
using your backup phrase. Be sure to enable a passcode on your device and use
[remote erase](http://www.apple.com/icloud/find-my-iphone.html#activation-lock)
if it is lost or stolen. Future versions of breadwallet will also include a
secondary passcode on the app itself.

![screenshot2](/images/screenshot2.jpg)

breadwallet is open source and available under the terms of the MIT license.
Source code is available at https://github.com/voisine/breadwallet

**WARNING:** installation on jailbroken devices is strongly discouraged

Any jailbreak app can grant itself keychain entitlements to your wallet seed and
rob you by self-signing as described [here](http://www.saurik.com/id/8) and
including `<key>application-identifier</key><string>org.voisine.*</string>` in
its .entitlements file.
