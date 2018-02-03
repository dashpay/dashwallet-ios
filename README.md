# Dashwallet

[![CI Status](http://img.shields.io/travis/QuantumExplorer/dashwalletsvg?style=flat)](https://travis-ci.org/QuantumExplorer/dashwallet)

<p align="center" >
<img src="DashWallet/Images.xcassets/AppIcon.appiconset/icon120.png" alt="Dashwallet" title="Dashwallet">
</p>

Dashwallet (breadwallet fork) is a real standalone Dash client. There is no server to get hacked or go down, so you can always access your money.
Using [SPV](https://en.bitcoin.it/wiki/Thin_Client_Security#Header-Only_Clients) mode, Dashwallet connects directly to the Dash network with the fast performance you need on a mobile device.

Dashwallet is designed to protect you from malware, browser security holes, even physical theft. With AES hardware encryption, app sandboxing,
keychain and code signatures, Dashwallet represents a significant security advantage over web and desktop wallets, and other mobile platforms.
Simplicity is Dashwallet’s core design principle. A simple backup phrase is all you need to restore your wallet on another device if yours is ever lost or broken.
Because Dashwallet is [deterministic](https://dashpay.atlassian.net/wiki/display/DOC/Whitepaper), your balance and transaction history can be recovered from just your backup phrase.

## Features:
- [“simplified payment verification”](https://dashpay.atlassian.net/wiki/display/DOC/Official+Documentation) for fast mobile performance
- no server to get hacked or go down
- single backup phrase that works forever
- private keys never leave your device
- import [password protected](https://dashpay.atlassian.net/wiki/display/DOC/Official+Documentation) paper wallets
- [“payment protocol”](https://dashpay.atlassian.net/wiki/display/DOC/Official+Documentation) payee identity certification
- Shapeshift integration (Pay any BTC Address by just scanning the BTC QR Code)

## URL scheme:
Dashwallet supports the [x-callback-url](http://x-callback-url.com/) specification with the following URLs:
```
dash://x-callback-url/address?x-success=myscheme://myaction
```
this will callback with the current wallet receive address: myscheme://myaction?address=1XXXX
the following will ask the user to authorize copying a list of their wallet addresses to the clipboard before calling back:
```
dash://x-callback-url/addresslist?x-success=myscheme://myaction
```

## WARNING:

installation on jailbroken devices is strongly discouraged

Any jailbreak app can grant itself access to every other app's keychain data
and rob you by self-signing as described [here](http://www.saurik.com/id/8)
and including `<key>application-identifier</key><string>*</string>` in its
.entitlements file.

## INSTALLATION:

[Download Install Guide](https://dashpay.atlassian.net/wiki/display/DOC/Download+-+Install+-+Guide)
