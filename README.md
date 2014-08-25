![ƀ](/images/icon.png) breadwallet
----------------------------------

[![download](/images/Download_on_the_App_Store_Badge_US-UK_135x40.png)]
(https://itunes.apple.com/app/breadwallet/id885251393)

An [SPV](https://en.bitcoin.it/wiki/Thin_Client_Security#Header-Only_Clients),
[BIP32](https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki)
deterministic bitcoin wallet for iOS

bitcoin done right 

the simplest and most secure bitcoin wallet on any platform 

![screenshot1](/images/screenshot1.jpg)

features: 

- the first real bitcoin client for iOS 
- doesn't rely on any server or web service 
- open source 
- single backup phrase that works forever 
- private keys never leave your device 
- "simplified payment verification" for fast mobile performance 
- import password protected paper wallets 
- "payment protocol" payee identity certification

![screenshot3](/images/screenshot3.jpg)

breadwallet is secure. It is designed to be secure against malware, security
issues in other apps, and even physical theft by taking full advantage of the
security features provided by iOS. This includes AES hardware encryption, app
sandboxing and data protection, code signing, and keychain services. If your
device is ever lost or broken, use your backup phrase to restore your balance
and transaction history on another device.

breadwallet uses "simplified payment verification" or
[SPV](https://en.bitcoin.it/wiki/Thin_Client_Security#Header-Only_Clients) mode
for fast performance in a mobile environment.

breadwallet is a 
[BIP32](https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki)
"deterministic" wallet, meaning that all the bitcoin addresses
and private keys are generated from a single "seed". If you know the seed, you
can recreate the entire wallet including all balances and transaction history.
This allows for a single convenient backup that will work forever.

![screenshot2](/images/screenshot2.jpg)

breadwallet is open source and available under the terms of the MIT license.
Source code is available at https://github.com/voisine/breadwallet

**WARNING:** installation on jailbroken devices is strongly discouraged

Any jailbreak app can grant itself access to every other app's keychain data
and rob you by self-signing as described [here](http://www.saurik.com/id/8)
and including `<key>application-identifier</key><string>*</string>` in its
.entitlements file.
