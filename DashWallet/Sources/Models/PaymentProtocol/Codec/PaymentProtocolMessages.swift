//
//  PaymentProtocolMessages.swift
//  DashWallet
//
//  BIP70 payment-protocol message model (Layer 1, pure Foundation).
//
//  The six proto2 messages from BIP70 (https://github.com/bitcoin/bips/blob/master/bip-0070.mediawiki)
//  with hand-rolled encode/decode over `ProtoReader`/`ProtoWriter`. Field numbers match
//  DashSync's `DSPaymentProtocol.m` enums exactly.
//
//  Byte-exactness rule (load-bearing for signature verification): a decoded
//  `PaymentRequest` keeps the *verbatim* field-4 details bytes (`serializedDetails`) and
//  re-emits them unchanged; it never round-trips `PaymentDetails` through the encoder.
//  See `PaymentRequest.encoded(signature:)`.
//
//  Pure: Foundation only, no I/O, no crypto, no SDK types.
//

import Foundation

// MARK: - Field numbers

private enum OutputField { static let amount = 1, script = 2 }
private enum DetailsField {
    static let network = 1, outputs = 2, time = 3, expires = 4, memo = 5, paymentURL = 6, merchantData = 7
}
private enum RequestField {
    static let version = 1, pkiType = 2, pkiData = 3, details = 4, signature = 5
}
private enum CertificatesField { static let certificate = 1 }
private enum PaymentField { static let merchantData = 1, transactions = 2, refundTo = 3, memo = 4 }
private enum ACKField { static let payment = 1, memo = 2 }

// MARK: - Output

/// A single payment output: an amount and a raw scriptPubKey. `amount == nil` means a
/// variable/unspecified amount (the reference omits the field, encoding `UINT64_MAX`).
struct PaymentOutput: Equatable {
    var amount: UInt64?
    var script: Data

    init(amount: UInt64?, script: Data) {
        self.amount = amount
        self.script = script
    }

    init(_ data: Data) {
        var reader = ProtoReader(data)
        var amount: UInt64?
        var script = Data()
        while let field = reader.readField() {
            switch field.field {
            case OutputField.amount: amount = field.varint
            case OutputField.script: if let d = field.data { script = d }
            default: break
            }
        }
        self.amount = amount
        self.script = script
    }

    func encoded() -> Data {
        var writer = ProtoWriter()
        if let amount { writer.append(key: OutputField.amount, varInt: amount) }
        writer.append(key: OutputField.script, data: script)
        return writer.data
    }
}

// MARK: - PaymentDetails

struct PaymentDetails {
    var network: String?
    var outputs: [PaymentOutput]
    var time: UInt64
    var expires: UInt64
    var memo: String?
    var paymentURL: String?
    var merchantData: Data?

    init(network: String?, outputs: [PaymentOutput], time: UInt64 = 0, expires: UInt64 = 0,
         memo: String? = nil, paymentURL: String? = nil, merchantData: Data? = nil) {
        self.network = network
        self.outputs = outputs
        self.time = time
        self.expires = expires
        self.memo = memo
        self.paymentURL = paymentURL
        self.merchantData = merchantData
    }

    init(_ data: Data) {
        var reader = ProtoReader(data)
        var network: String?
        var outputs: [PaymentOutput] = []
        var time: UInt64 = 0
        var expires: UInt64 = 0
        var memo: String?
        var paymentURL: String?
        var merchantData: Data?
        while let field = reader.readField() {
            switch field.field {
            case DetailsField.network: network = field.data.flatMap { String(data: $0, encoding: .utf8) }
            case DetailsField.outputs: if let d = field.data { outputs.append(PaymentOutput(d)) }
            case DetailsField.time: time = field.varint ?? 0
            case DetailsField.expires: expires = field.varint ?? 0
            case DetailsField.memo: memo = field.data.flatMap { String(data: $0, encoding: .utf8) }
            case DetailsField.paymentURL: paymentURL = field.data.flatMap { String(data: $0, encoding: .utf8) }
            case DetailsField.merchantData: merchantData = field.data
            default: break
            }
        }
        self.network = network
        self.outputs = outputs
        self.time = time
        self.expires = expires
        self.memo = memo
        self.paymentURL = paymentURL
        self.merchantData = merchantData
    }

    func encoded() -> Data {
        var writer = ProtoWriter()
        if let network { writer.append(key: DetailsField.network, string: network) }
        for output in outputs { writer.append(key: DetailsField.outputs, data: output.encoded()) }
        if time >= 1 { writer.append(key: DetailsField.time, varInt: time) }
        if expires >= 1 { writer.append(key: DetailsField.expires, varInt: expires) }
        if let memo { writer.append(key: DetailsField.memo, string: memo) }
        if let paymentURL { writer.append(key: DetailsField.paymentURL, string: paymentURL) }
        if let merchantData { writer.append(key: DetailsField.merchantData, data: merchantData) }
        return writer.data
    }
}

// MARK: - PaymentRequest

struct PaymentRequest {
    /// Present-or-absent preserved (nil = absent) so the re-encode is byte-exact; logic uses `version ?? 1`.
    var version: UInt64?
    var pkiType: String
    var pkiData: Data?
    /// Verbatim field-4 bytes as received. Re-emitted unchanged; never round-tripped.
    var serializedDetails: Data
    var signature: Data?

    /// Decoded lazily for display/logic. The encoder never uses this.
    var details: PaymentDetails { PaymentDetails(serializedDetails) }

    init(version: UInt64? = 1, pkiType: String = "none", pkiData: Data? = nil,
         serializedDetails: Data, signature: Data? = nil) {
        self.version = version
        self.pkiType = pkiType
        self.pkiData = pkiData
        self.serializedDetails = serializedDetails
        self.signature = signature
    }

    init?(_ data: Data) {
        var reader = ProtoReader(data)
        var version: UInt64?
        var pkiType = "none"
        var pkiData: Data?
        var serializedDetails: Data?
        var signature: Data?
        while let field = reader.readField() {
            switch field.field {
            case RequestField.version: version = field.varint
            case RequestField.pkiType: if let s = field.data.flatMap({ String(data: $0, encoding: .utf8) }) { pkiType = s }
            case RequestField.pkiData: pkiData = field.data
            case RequestField.details: serializedDetails = field.data
            case RequestField.signature: signature = field.data
            default: break
            }
        }
        guard let serializedDetails else { return nil } // details (field 4) is required
        self.version = version
        self.pkiType = pkiType
        self.pkiData = pkiData
        self.serializedDetails = serializedDetails
        self.signature = signature
    }

    /// Encodes in ascending field order. `signature` replaces `self.signature` for this
    /// encode — pass an empty `Data()` to reproduce the bytes the merchant signed over
    /// (signature field present, zero length → `2a 00`), or `nil` to omit it.
    func encoded(signature signatureOverride: Data?) -> Data {
        var writer = ProtoWriter()
        if let version { writer.append(key: RequestField.version, varInt: version) }
        writer.append(key: RequestField.pkiType, string: pkiType)
        if let pkiData { writer.append(key: RequestField.pkiData, data: pkiData) }
        writer.append(key: RequestField.details, data: serializedDetails)
        if let signatureOverride { writer.append(key: RequestField.signature, data: signatureOverride) }
        return writer.data
    }

    /// Full wire encoding including the real signature.
    func encoded() -> Data { encoded(signature: signature) }
}

// MARK: - X509Certificates (carried in PaymentRequest.pkiData)

struct X509Certificates {
    var certificates: [Data]

    init(certificates: [Data]) { self.certificates = certificates }

    init(_ data: Data) {
        var reader = ProtoReader(data)
        var certificates: [Data] = []
        while let field = reader.readField() {
            if field.field == CertificatesField.certificate, let d = field.data { certificates.append(d) }
        }
        self.certificates = certificates
    }

    func encoded() -> Data {
        var writer = ProtoWriter()
        for cert in certificates { writer.append(key: CertificatesField.certificate, data: cert) }
        return writer.data
    }
}

// MARK: - Payment (customer → merchant)

struct Payment {
    var merchantData: Data?
    var transactions: [Data]
    var refundTo: [PaymentOutput]
    var memo: String?

    init(merchantData: Data? = nil, transactions: [Data], refundTo: [PaymentOutput] = [], memo: String? = nil) {
        self.merchantData = merchantData
        self.transactions = transactions
        self.refundTo = refundTo
        self.memo = memo
    }

    init(_ data: Data) {
        var reader = ProtoReader(data)
        var merchantData: Data?
        var transactions: [Data] = []
        var refundTo: [PaymentOutput] = []
        var memo: String?
        while let field = reader.readField() {
            switch field.field {
            case PaymentField.merchantData: merchantData = field.data
            case PaymentField.transactions: if let d = field.data { transactions.append(d) }
            case PaymentField.refundTo: if let d = field.data { refundTo.append(PaymentOutput(d)) }
            case PaymentField.memo: memo = field.data.flatMap { String(data: $0, encoding: .utf8) }
            default: break
            }
        }
        self.merchantData = merchantData
        self.transactions = transactions
        self.refundTo = refundTo
        self.memo = memo
    }

    func encoded() -> Data {
        var writer = ProtoWriter()
        if let merchantData { writer.append(key: PaymentField.merchantData, data: merchantData) }
        for tx in transactions { writer.append(key: PaymentField.transactions, data: tx) }
        for output in refundTo { writer.append(key: PaymentField.refundTo, data: output.encoded()) }
        if let memo { writer.append(key: PaymentField.memo, string: memo) }
        return writer.data
    }
}

// MARK: - PaymentACK (merchant → customer)

struct PaymentACK {
    var payment: Payment?
    var memo: String?

    init(payment: Payment?, memo: String? = nil) {
        self.payment = payment
        self.memo = memo
    }

    init(_ data: Data) {
        var reader = ProtoReader(data)
        var payment: Payment?
        var memo: String?
        while let field = reader.readField() {
            switch field.field {
            case ACKField.payment: if let d = field.data { payment = Payment(d) }
            case ACKField.memo: memo = field.data.flatMap { String(data: $0, encoding: .utf8) }
            default: break
            }
        }
        self.payment = payment
        self.memo = memo
    }

    func encoded() -> Data {
        var writer = ProtoWriter()
        if let payment { writer.append(key: ACKField.payment, data: payment.encoded()) }
        if let memo { writer.append(key: ACKField.memo, string: memo) }
        return writer.data
    }
}
