# BIP70 Testing Guide

Practical notes for exercising the BIP70 (X.509-signed payment-protocol) send flow in
dashwallet-ios, gathered while scoping the migration of BIP70 **off DashSync** (see
[`DASHSYNC_MIGRATION.md`](./DASHSYNC_MIGRATION.md) row #22). This is the harness + findings;
the implementation plan for re-doing BIP70 app-side (outside DashSync) is a separate doc.

---

## TL;DR — what we proved

| Layer | Status | How we know |
|---|---|---|
| BIP70 **fetch + X.509 signature verify + protobuf parse** | ✅ **works** | Self-verified in Node (`SecKeyRawVerify`-equivalent passes), then the wallet actually fetched our signed request (server access log). |
| Confirm UI via `simctl openurl` | ⚠️ **finicky** | Address-**ful** `dash:addr?…&r=` → plain-send path (amount keypad); address-**less** `dash:?r=` → fetches but no UI context to present the confirm. |
| BIP70 **send** (sign → broadcast → Payment/ACK) | ❌ **dead on this build** | No `POST /payment` ever reaches the merchant; the legacy send signs from DashSync's frozen account. |

**Why the send is dead:** BIP70 routes to `DSTransactionManager confirmProtocolRequest:fromAccount:[DWEnvironment currentAccount]` — DashSync's account. The app no longer calls DashSync `startSync` (SPV is frozen post-M6), so that account has no UTXOs (the real coins live in the SwiftDashSDK wallet). Coin selection fails → no tx is built → nothing is POSTed. **This is exactly what the port fixes** by routing the send through SwiftDashSDK's funded wallet.

**Why BIP70 can't just be dropped:** the **CTX gift-card** purchase flow uses real BIP70 with a live `r=` endpoint — see [`DashSpendPayViewModel.swift:241`](DashWallet/Sources/UI/Explore%20Dash/Views/DashSpend/DashSpendPayViewModel.swift#L241) (`// CTX uses BIP70 payment request URLs` → `sendCoinsService.payWithDashUrl`). PiggyCards does **not** (plain `sendCoins`).

---

## The test server (HashEngineering/bip70-dash)

A self-contained Node BIP70 merchant ("Dash Sticker", 0.001 DASH). It is the **payee/merchant**
side — the wallet is only the client. Repo: <https://github.com/HashEngineering/bip70-dash>

### Get it

```bash
git clone https://github.com/HashEngineering/bip70-dash.git
cd bip70-dash
npm install            # Node v16+
npm run generate-certs # self-signed cert, CN "Dash Sticker Shop", RSA-2048, sha256
```

### `.env` (testnet) — uses a public testnet xpub from the repo README

```
DASH_XPUB=tpubDD6g4gvM411BjuveqKNjzApMsjQzywdgjhjWcmiWVNa3A1tMMUe4LFFYUhEy11p5uWP3KrJHMxN6r2rws9wFJiqazTv2PsPE34c8py7dREU
DASH_NETWORK=testnet
RPC_USER=left
RPC_PASSWORD=right
RPC_HOST=127.0.0.1
RPC_PORT=19998
```

> The xpub is **public/shared** — addresses derived from it are not yours. Fine for protocol
> testing; if you want to recover sent coins, put **your** testnet xpub here.

### Run it

```bash
node server.js
# HTTP  :3000  ← wallet hits this (the r= URL)
# HTTPS :3001  ← browser storefront (self-signed)
```

### Endpoints / behaviour

| Endpoint | Purpose |
|---|---|
| `GET /` | Storefront page; **mints a new payment** (`id` = sequential, +1 each load), derives an address `m/0/<id>`, returns a QR + `dash:` URI |
| `GET /payment-request?id=N` | The BIP70 `PaymentRequest` protobuf (`application/dash-paymentrequest`) |
| `POST /payment` | Receives the `Payment` protobuf, broadcasts via RPC, returns `PaymentACK` |
| `GET /status?id=N` | Live in-memory status: `pending` → `mempool` → `confirmed` |

- **Dash Core is NOT required to serve a request.** RPC errors are caught silently. Core
  (testnet, `server=1`, creds matching `.env`) is only needed to actually **broadcast** the tx
  and flip `/status` to `confirmed`.
- `dash:` URI format (BIP72): `dash:<addr>?amount=0.001&r=<urlencoded http://IP:3000/payment-request?id=N>`.

### Local patch we applied (not in upstream)

Upstream serves `pki_type = "none"` (**unsigned**) despite the README. To test X.509
verification we patched `server.js`:

1. `const crypto = require('crypto');`
2. `const SIGN_REQUESTS = process.env.PKI_NONE !== '1';` — default sign; `PKI_NONE=1` reverts to unsigned.
3. `const X509Certificates = root.lookupType('payments.X509Certificates');`
4. Bumped `expires` from `+60` to `+3600` (60 s is too short to test through).
5. Unbuffered `access.log` (`fs.appendFileSync`) on `GET /payment-request` and `POST /payment`
   (because `console.log` to a backgrounded pipe buffers and hid events).
6. The signing itself in `GET /payment-request` — sign the request serialized **with an empty
   (but present) signature field**, fields ascending, exactly what the wallet reconstructs:

```js
const certDer = new crypto.X509Certificate(serverCert).raw;                 // leaf DER
const pkiData = X509Certificates.encode(
  X509Certificates.create({ certificate: [certDer] })).finish();
const base = { paymentDetailsVersion: 1, pkiType: 'x509+sha256',
               pkiData, serializedPaymentDetails: serializedDetails };
const toSign = PaymentRequest.encode(
  PaymentRequest.create({ ...base, signature: Buffer.alloc(0) })).finish(); // empty sig field = 2a 00
const signature = crypto.sign('sha256', toSign,
  { key: serverKey, padding: crypto.constants.RSA_PKCS1_PADDING });         // RSA-PKCS1v15 over SHA256
const requestBytes = PaymentRequest.encode(
  PaymentRequest.create({ ...base, signature })).finish();
```

**Why this is byte-exact with the wallet:** `DSPaymentProtocol.isValid`
([`DSPaymentProtocol.m:453`](../DashSync/DashSync/shared/Models/Payment/DSPaymentProtocol.m#L453))
zeroes `_signature` then re-serializes (`toData`, ascending fields, empty-sig field written as
`2a 00`), SHA256s it, and `SecKeyRawVerify(kSecPaddingPKCS1SHA256)`. The parsed
`serialized_payment_details` is cached verbatim (`initWithData:` → `self.data = data`), so the
inner details bytes are re-emitted unchanged. We confirmed the server's signed digest equals
the reconstruction digest in Node — the signature passes the wallet's verify step.

---

## Triggering from the wallet (simulator)

> Build/run note (this branch): scheme **`dashpay`**, **testnet**, force **`ARCHS=arm64`**
> (FFI libs are arm64-sim only; `dashwallet` scheme is broken on this branch). ATS is already
> off (`NSAllowsArbitraryLoads = true` in [`Info.plist`](DashWallet/Info.plist)), so plain
> `http://` works.

### The fallback-address gotcha (important)

There are two `dash:` URI shapes and they take **different paths**:

| URI shape | Wallet behaviour |
|---|---|
| `dash:<addr>?amount=0.001&r=…` (with fallback addr) | [`DWPaymentInputBuilder.m:50`](DashWallet/Sources/UI/Payments/PaymentModels/DWPaymentInputBuilder.m#L50) sees a valid address → **plain-send** path (amount keypad). BIP70 fetch is deferred to **Send** ([`DWPaymentProcessor.m:349`](DashWallet/Sources/UI/Payments/PaymentModels/DWPaymentProcessor.m#L349)) and falls back to the address if the fetch errors. |
| `dash:?r=…` (**address-less**, like CTX) | No address to fall back to → the wallet **must fetch** the BIP70 request. This is the form that exercises the protocol. |

### Fire a request

```bash
# mint a fresh request, strip to the address-less form, point r= at localhost (sim → Mac)
RAW=$(curl -s http://localhost:3000/ | grep -oE 'dash:[^<"]+' | head -1)
R=$(echo "$RAW" | grep -oE 'r=[^&"]+' | sed 's/^r=//' | sed 's/192\.168\.0\.[0-9]*/localhost/')
URI="dash:?r=$R"

# fire at the booted simulator (use the UDID if more than one is booted)
xcrun simctl openurl booted "$URI"
```

- **Simulator** reaches the Mac via `localhost:3000` or the LAN IP. **Physical device** must use
  the LAN IP and be on the same Wi-Fi.
- Confirm the wallet fetched: `cat bip70-dash/access.log` → `GET /payment-request id=N … wallet FETCHED`.

### Make the cert trusted (for the verified-merchant path)

`isValid` needs **both** a valid signature **and** `SecTrustEvaluateWithError` to pass. The
self-signed cert fails trust until you install it:

```bash
xcrun simctl keychain booted add-root-cert /path/to/bip70-dash/certs/server.crt
```

Without it you get "Untrusted certificate"; with it the confirm shows the verified merchant
name **"Dash Sticker Shop"**.

---

## What we observed (this session)

- Address-less `dash:?r=` → wallet **auto-fetched** the signed request on open (`access.log`
  shows `pki=x509+sha256`), but **no confirm screen appeared** — the deep-link had no UI context
  to present into (and/or the untrusted cert bailed silently). The fetch itself is the proof the
  protocol layer works.
- Address-ful `dash:addr?…&r=` → showed the plain **amount keypad → Confirm** (Total = `0.001`
  with the fee carved out → plain-send), never the BIP70 confirm. When the server was down at
  Send time, it fell back to a plain send to the embedded address.
- `/status` for every id stayed `pending`; **no `POST /payment` ever arrived** → the send never
  completed (frozen DashSync account).

### Diagnostics

```bash
# did the wallet fetch / send?
cat bip70-dash/access.log

# DashSync account balance (should be ~0 vs the SwiftDashSDK home-screen balance) — lldb:
po (uint64_t)[[DWEnvironment sharedInstance].currentAccount balance]

# wallet os_log from the sim
xcrun simctl spawn booted log show --last 2m --predicate 'eventMessage CONTAINS[c] "payment"'
```

---

## How BIP70 is wired in the wallet (code map — for the port)

- **Entry points** funnel into `DSPaymentRequest`: QR (`r=`), `dash:`/`pay:`/`dashwallet:` deep
  links, `.dashpaymentrequest` UTI, pasteboard, Apple Watch, and programmatic
  `SendCoinsService.payWithDashUrl`.
- **Fetch** (`fetchBIP70`): [`DWQRScanModel.m:204`](DashWallet/Sources/UI/Payments/ScanQR/DWQRScanModel.m#L204)
  (QR, fetch-then-present — the canonical path), [`DWPaymentInputBuilder.m:94`](DashWallet/Sources/UI/Payments/PaymentModels/DWPaymentInputBuilder.m#L94)
  (BIP73), [`DWPaymentProcessor.m:351`](DashWallet/Sources/UI/Payments/PaymentModels/DWPaymentProcessor.m#L351) (on Send).
- **The BIP70 gate**: [`DWPaymentProcessor.m:398`](DashWallet/Sources/UI/Payments/PaymentModels/DWPaymentProcessor.m#L398)
  `hasBIP70 = protocolRequest.details.paymentURL.length > 0`. Every **non-BIP70** plain send
  already routes through SwiftDashSDK (`confirmProtocolRequestViaSwiftDashSDK`); **BIP70 is the
  one branch still on DashSync's `DSTransactionManager`.**
- **Reference implementation to port** (Obj-C, ~1219 LOC, no OpenSSL — hand-rolled protobuf +
  Apple `Security.framework`):
  - [`DSPaymentProtocol.m`](../DashSync/DashSync/shared/Models/Payment/DSPaymentProtocol.m) (705) — protobuf codec, the 4 messages, `isValid` (X.509 + signature).
  - `DSPaymentRequest.m` (514) — URI parsing, `fetchBIP70`.
- **SDK gap**: SwiftDashSDK / Rust FFI have **zero** BIP70 (no protobuf, X.509, or HTTP). 100%
  of the protocol logic is app-side Swift; the SDK only provides the send primitive
  (`sendToAddresses`) underneath.

### BIP70 protobuf messages (from the server's `payments.proto`, proto2)

`Output{amount,script}`, `PaymentDetails{network,outputs,time,expires,memo,payment_url,merchant_data}`,
`PaymentRequest{payment_details_version,pki_type,pki_data,serialized_payment_details,signature}`,
`Payment{merchant_data,transactions,refund_to,memo}`, `PaymentACK{payment,memo}`,
`X509Certificates{certificate[]}`.

---

## Next step

Plan the app-side reimplementation (Swift, outside DashSync) — protobuf codec, the 4 messages +
Dash deviations, `Security.framework` X.509 verify, URLSession transport — feeding outputs into
SwiftDashSDK `sendToAddresses`, and dropping the `hasBIP70` guard. This server is the test
harness for that work.
