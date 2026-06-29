//
//  PaymentProtocolTransport.swift
//  DashWallet
//
//  BIP70 payment-protocol — HTTP transport (Layer 3).
//
//  The only layer that talks to the merchant server: fetch the signed PaymentRequest, POST
//  the Payment, read the PaymentACK. Reproduces DashSync's `DSPaymentRequest` HTTP contract
//  (scheme-parameterized content types, ≤50 KB cap, MIME check, BIP73 text/uri-list) and
//  mirrors `SwiftDashSDKInsightClient` (ephemeral URLSession injected via init, so tests
//  drive it with `MockURLProtocol`).
//
//  Pure transport: it decodes bytes into L1 messages but does NOT verify signatures (L2),
//  check the network/expiry (L5), or interpret the ACK (L5). No UIKit / DashSync / SDK.
//

import Foundation

protocol PaymentProtocolTransporting {
    func fetchRequest(from url: URL, scheme: String) async throws -> PaymentRequest
    func postPayment(_ payment: Payment, to url: URL, scheme: String) async throws -> PaymentACK
}

final class PaymentProtocolTransport: PaymentProtocolTransporting {

    /// BIP70 caps payment-protocol payloads at 50 KB.
    private static let maxPayloadBytes = 50_000
    private static let timeout: TimeInterval = 30

    private let session: URLSession

    init(session: URLSession = PaymentProtocolTransport.makeDefaultSession()) {
        self.session = session
    }

    static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    // MARK: - Fetch

    func fetchRequest(from url: URL, scheme: String) async throws -> PaymentRequest {
        try await fetchRequest(from: url, scheme: scheme, followURIList: true)
    }

    /// `followURIList` guards BIP73 to a single hop (the uri-list may point at the real
    /// request; we never recurse beyond that).
    private func fetchRequest(from url: URL, scheme: String, followURIList: Bool) async throws -> PaymentRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.timeout)
        request.setValue("application/\(scheme)-paymentrequest", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        let http = try validate(response, data: data, host: url.host)

        switch http.mimeType?.lowercased() {
        case "application/\(scheme)-paymentrequest":
            guard let paymentRequest = PaymentRequest(data) else { throw BIP70Error.malformedRequest }
            return paymentRequest
        case "text/uri-list" where followURIList:
            // BIP73: the body is a list of URLs; fetch the first non-comment one once.
            guard let next = Self.firstURL(inURIList: data) else { throw BIP70Error.unexpectedResponse(host: url.host) }
            return try await fetchRequest(from: next, scheme: scheme, followURIList: false)
        default:
            throw BIP70Error.unexpectedResponse(host: url.host)
        }
    }

    // MARK: - Post

    func postPayment(_ payment: Payment, to url: URL, scheme: String) async throws -> PaymentACK {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.setValue("application/\(scheme)-payment", forHTTPHeaderField: "Content-Type")
        request.setValue("application/\(scheme)-paymentack", forHTTPHeaderField: "Accept")
        request.httpBody = payment.encoded()

        let (data, response) = try await session.data(for: request)
        let http = try validate(response, data: data, host: url.host)
        guard http.mimeType?.lowercased() == "application/\(scheme)-paymentack" else {
            throw BIP70Error.unexpectedResponse(host: url.host)
        }
        return PaymentACK(data)
    }

    // MARK: - Helpers

    private func validate(_ response: URLResponse, data: Data, host: String?) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else { throw BIP70Error.unexpectedResponse(host: host) }
        guard (200..<300).contains(http.statusCode) else { throw BIP70Error.unexpectedResponse(host: host) }
        guard data.count <= Self.maxPayloadBytes else { throw BIP70Error.payloadTooLarge }
        return http
    }

    private static func firstURL(inURIList data: Data) -> URL? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            return URL(string: trimmed)
        }
        return nil
    }
}
