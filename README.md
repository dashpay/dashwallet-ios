![ƀ](/images/icon.png) breadwallet
----------------------------------

[![download](/images/Download_on_the_App_Store_Badge_US-UK_135x40.png)]
(https://itunes.apple.com/app/breadwallet/id885251393)

**bitcoin done right**

the simplest and most secure bitcoin wallet on any platform 

![screenshot1](/images/screenshot1.jpg)

**the first standalone iOS bitcoin wallet:**

Unlike other iOS bitcoin wallets, breadwallet is a real standalone bitcoin
client. There is no server to get hacked or go down, so you can always access
your money. Using
[SPV](https://en.bitcoin.it/wiki/Thin_Client_Security#Header-Only_Clients)
mode, breadwallet connects directly to the bitcoin network with the fast
performance you need on a mobile device.

**the next step in wallet security:**

breadwallet is designed to protect you from malware, browser security holes,
*even physical theft*. With AES hardware encryption, app sandboxing, keychain
and code signatures, breadwallet represents a significant security advance over
web and desktop wallets, and other mobile platforms.

**beautiful simplicity:**

Simplicity is breadwallet's core design principle. A simple backup phrase is
all you need to restore your wallet on another device if yours is ever lost or
broken.  Because breadwallet is  
[deterministic](https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki),
your balance and transaction history can be recovered from just your backup
phrase.

![screenshot2](/images/screenshot2.jpg)

**features:**

- ["simplified payment verification"](https://github.com/bitcoin/bips/blob/master/bip-0037.mediawiki) for fast mobile performance
- no server to get hacked or go down
- single backup phrase that works forever
- private keys never leave your device
- import [password protected](https://github.com/bitcoin/bips/blob/master/bip-0038.mediawiki) paper wallets
- ["payment protocol"](https://github.com/bitcoin/bips/blob/master/bip-0070.mediawiki) payee identity certification

breadwallet is open source and available under the terms of the MIT license.
Source code is available at https://github.com/voisine/breadwallet

**WARNING:** installation on jailbroken devices is strongly discouraged

Any jailbreak app can grant itself access to every other app's keychain data
and rob you by self-signing as described [here](http://www.saurik.com/id/8)
and including `<key>application-identifier</key><string>*</string>` in its
.entitlements file.
