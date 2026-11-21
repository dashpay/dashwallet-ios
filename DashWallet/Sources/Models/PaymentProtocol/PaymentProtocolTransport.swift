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
        guard Self.isSecure(url) else { throw BIP70Error.badURL }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.timeout)
        request.setValue("application/\(scheme)-paymentrequest", forHTTPHeaderField: "Accept")

        let (data, http) = try await receive(request, host: url.host)

        switch http.mimeType?.lowercased() {
        case "application/\(scheme)-paymentrequest":
            guard let paymentRequest = PaymentRequest(data) else { throw BIP70Error.malformedRequest }
            return paymentRequest
        case "text/uri-list" where followURIList:
            // BIP73: the body is a list of URLs; fetch the first non-comment one once.
            guard let next = Self.firstURL(inURIList: data) else {
                throw BIP70Error.unexpectedResponse(host: url.host)
            }
            return try await fetchRequest(from: next, scheme: scheme, followURIList: false)
        default:
            throw BIP70Error.unexpectedResponse(host: url.host)
        }
    }

    // MARK: - Post

    func postPayment(_ payment: Payment, to url: URL, scheme: String) async throws -> PaymentACK {
        guard Self.isSecure(url) else { throw BIP70Error.badURL }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.setValue("application/\(scheme)-payment", forHTTPHeaderField: "Content-Type")
        request.setValue("application/\(scheme)-paymentack", forHTTPHeaderField: "Accept")
        request.httpBody = payment.encoded()

        let (data, http) = try await receive(request, host: url.host)
        guard http.mimeType?.lowercased() == "application/\(scheme)-paymentack" else {
            throw BIP70Error.unexpectedResponse(host: url.host)
        }
        return PaymentACK(data)
    }

    // MARK: - Helpers

    /// The body is read against the 50 KB cap as it arrives, so a merchant
    /// that sends more is cut off instead of buffered whole.
    private func receive(_ request: URLRequest, host: String?) async throws -> (Data, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request, delegate: HTTPSOnlyRedirects())
        do {
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw BIP70Error.unexpectedResponse(host: host)
            }
            // Redirects off https are refused before they are made; this backs that up.
            if let served = http.url, !Self.isSecure(served) {
                throw BIP70Error.unexpectedResponse(host: host)
            }
            guard http.expectedContentLength <= Int64(Self.maxPayloadBytes) else {
                throw BIP70Error.payloadTooLarge
            }
            var data = Data()
            for try await byte in bytes {
                guard data.count < Self.maxPayloadBytes else { throw BIP70Error.payloadTooLarge }
                data.append(byte)
            }
            return (data, http)
        } catch {
            bytes.task.cancel()
            throw error
        }
    }

    /// Unsigned requests are allowed, so the channel is the only thing authenticating the merchant.
    static func isSecure(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.isEmpty == false
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

/// Refuses a redirect off https before it is followed, so nothing is sent in the clear.
private final class HTTPSOnlyRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        request.url.map(PaymentProtocolTransport.isSecure) == true ? request : nil
    }
}
