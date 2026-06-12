//
//  PhraseRepairEngineTests.swift
//  DashWalletTests
//
//  Unit tests for the pure-Swift phrase-repair engine
//  (`SwiftDashSDKPhraseRepairer` / `PhraseRepairEngine`), its Insight
//  HTTP client, and the Damerau-Levenshtein backup ranking.
//
//  The two-missing-words path (`findTwoMissingWords`) is exercised only
//  through its building blocks here: an end-to-end run brute-forces
//  2048 × 2048 checksum validations through the FFI (minutes, networked),
//  which is a manual smoke-test concern, not a unit-test one.
//
//  NOTE: the DashWalletTests bundle is pre-existing broken (TodayExtension
//  `DSDynamicOptions` link failure stops the run). These tests compile
//  against the `dashwallet` target (all types under test are registered
//  there) and run once the bundle is repaired; until then they are
//  build-validated via `xcodebuild build-for-testing`.
//

import XCTest
import SwiftDashSDK
@testable import dashwallet

// MARK: - Helpers

private let abandon11 = Array(repeating: "abandon", count: 11)

private func makeDependencies(
    existing: Set<String> = [],
    insightError: Error? = nil,
    derive: @escaping (String) -> String? = { phrase in
        "ADDR-" + (phrase.split(separator: " ").last.map(String.init) ?? "?")
    }
) -> PhraseRepairEngine.Dependencies {
    PhraseRepairEngine.Dependencies(
        insight: MockInsight(existing: existing, error: insightError),
        deriveFirstAddress: derive
    )
}

private struct MockInsight: InsightAddressQuerying {
    var existing: Set<String>
    var error: Error?

    func findExistingAddresses(_ addresses: [String]) async throws -> Set<String> {
        if let error { throw error }
        return existing.intersection(addresses)
    }
}

private struct StubError: Error {}

private let neverStop: PhraseRepairEngine.ProgressTick = { _ in false }

// MARK: - Candidate scan (real SDK checksum + real FFI derivation)

final class PhraseRepairCandidateScanTests: XCTestCase {

    /// Any 11-word prefix admits exactly 2^7 = 128 checksum-valid last
    /// words (the last word carries 7 entropy bits + 4 checksum bits).
    func testAbandonPrefixYields128CandidatesIncludingAbout() async {
        let scan = await PhraseRepairEngine.scanCandidates(
            remaining: abandon11,
            insertIndex: 11,
            language: .english,
            dependencies: makeDependencies(derive: PhraseRepairEngine.defaultDeriveFirstAddress),
            progress: neverStop
        )

        XCTAssertFalse(scan.stopped)
        XCTAssertEqual(scan.checksumValidWords.count, 128)
        XCTAssertTrue(scan.checksumValidWords.contains("about"))

        // English candidates all derive (FFI succeeds): distinct mainnet
        // P2PKH addresses, one per word.
        XCTAssertEqual(scan.addressToWord.count, 128)
        for address in scan.addressToWord.keys {
            XCTAssertTrue(address.hasPrefix("X"), "mainnet P2PKH expected, got \(address)")
        }
    }

    /// The derivation chain is deterministic — same candidate, same address.
    func testDerivationIsDeterministic() {
        let phrase = (abandon11 + ["about"]).joined(separator: " ")
        let first = PhraseRepairEngine.defaultDeriveFirstAddress(phrase: phrase)
        let second = PhraseRepairEngine.defaultDeriveFirstAddress(phrase: phrase)
        XCTAssertNotNil(first)
        XCTAssertEqual(first, second)
    }

    func testStopFlagAbortsScan() async {
        let scan = await PhraseRepairEngine.scanCandidates(
            remaining: abandon11,
            insertIndex: 11,
            language: .english,
            dependencies: makeDependencies(),
            progress: { _ in true } // stop at the first tick
        )
        XCTAssertTrue(scan.stopped)
        XCTAssertLessThan(scan.checksumValidWords.count, 128)
    }
}

// MARK: - Best-fitting language

final class PhraseRepairLanguageTests: XCTestCase {

    func testEnglishWordsPickEnglish() {
        XCTAssertEqual(PhraseRepairEngine.bestFittingLanguage(for: ["abandon", "ability", "zoo"]),
                       .english)
    }

    func testEmptyInputFallsBackToEnglish() {
        XCTAssertEqual(PhraseRepairEngine.bestFittingLanguage(for: []), .english)
        XCTAssertEqual(PhraseRepairEngine.bestFittingLanguage(for: ["notaword"]), .english)
    }

    /// One word from two disjoint lists each → tied counts → deterministic
    /// lowest-rawValue winner (deviation 2; English == 0 wins every tie
    /// it participates in).
    func testTieBreaksByRawValue() {
        let spanishOnly = Set(Mnemonic.wordList(language: .spanish))
            .subtracting(Mnemonic.wordList(language: .english))
        let englishOnly = Set(Mnemonic.wordList(language: .english))
            .subtracting(Mnemonic.wordList(language: .spanish))
        guard let spanishWord = spanishOnly.first, let englishWord = englishOnly.first else {
            return XCTFail("wordlists unexpectedly identical")
        }
        XCTAssertEqual(PhraseRepairEngine.bestFittingLanguage(for: [englishWord, spanishWord]),
                       .english)
    }
}

// MARK: - Damerau-Levenshtein

final class DamerauLevenshteinTests: XCTestCase {

    func testDistances() {
        XCTAssertEqual(DamerauLevenshtein.distance("zoo", "zoo"), 0)
        XCTAssertEqual(DamerauLevenshtein.distance("", "abc"), 3)
        XCTAssertEqual(DamerauLevenshtein.distance("abc", ""), 3)
        XCTAssertEqual(DamerauLevenshtein.distance("ab", "ba"), 1) // transposition
        XCTAssertEqual(DamerauLevenshtein.distance("abandno", "abandon"), 1) // transposition
        XCTAssertEqual(DamerauLevenshtein.distance("cat", "cats"), 1) // insertion
        XCTAssertEqual(DamerauLevenshtein.distance("cats", "cat"), 1) // deletion
        XCTAssertEqual(DamerauLevenshtein.distance("cat", "bat"), 1) // substitution
        XCTAssertEqual(DamerauLevenshtein.distance("abc", "xyz"), 3) // beyond backup cutoff
    }
}

// MARK: - Engine (mocked Insight + derivation)

final class PhraseRepairEngineTests: XCTestCase {

    /// On-chain confirmation wins: the word whose address Insight knows
    /// comes back with Max confidence (0).
    func testOnChainConfirmedWordWins() async {
        let phrase = (abandon11 + ["zzzz"]).joined(separator: " ")
        let result = await PhraseRepairEngine.findPotentialWords(
            passphrase: phrase,
            replacement: "zzzz",
            language: nil,
            useDistanceAsBackup: true,
            dependencies: makeDependencies(existing: ["ADDR-about"]),
            progress: neverStop
        )
        XCTAssertEqual(result, ["about": 0])
    }

    /// No on-chain match → distance-ranked checksum-valid suggestions.
    func testDistanceBackupRanksTypoNeighbors() async {
        let phrase = (abandon11 + ["abouz"]).joined(separator: " ")
        let result = await PhraseRepairEngine.findPotentialWords(
            passphrase: phrase,
            replacement: "abouz",
            language: nil,
            useDistanceAsBackup: true,
            dependencies: makeDependencies(existing: []),
            progress: neverStop
        )
        XCTAssertEqual(result["about"], 1)
        XCTAssertFalse(result.values.contains { $0 >= 3 })
        XCTAssertFalse(result.isEmpty)
    }

    /// Insight network failure degrades exactly like "no matches".
    func testInsightErrorDegradesToDistanceBackup() async {
        let phrase = (abandon11 + ["abouz"]).joined(separator: " ")
        let result = await PhraseRepairEngine.findPotentialWords(
            passphrase: phrase,
            replacement: "abouz",
            language: nil,
            useDistanceAsBackup: true,
            dependencies: makeDependencies(insightError: StubError()),
            progress: neverStop
        )
        XCTAssertEqual(result["about"], 1)
    }

    /// Without the backup flag (find-last flow), no match means empty.
    func testNoBackupMeansEmptyOnMiss() async {
        let phrase = (abandon11 + ["zzzz"]).joined(separator: " ")
        let result = await PhraseRepairEngine.findPotentialWords(
            passphrase: phrase,
            replacement: "zzzz",
            language: nil,
            useDistanceAsBackup: false,
            dependencies: makeDependencies(existing: []),
            progress: neverStop
        )
        XCTAssertTrue(result.isEmpty)
    }

    /// Deviation 1: counts ∉ {10, 11} complete with {} instead of hanging.
    func testUnsupportedWordCountReturnsEmpty() async {
        let phrase = (Array(abandon11.prefix(8)) + ["zzzz"]).joined(separator: " ")
        let result = await PhraseRepairEngine.findPotentialWords(
            passphrase: phrase,
            replacement: "zzzz",
            language: nil,
            useDistanceAsBackup: true,
            dependencies: makeDependencies(existing: ["ADDR-about"]),
            progress: neverStop
        )
        XCTAssertTrue(result.isEmpty)
    }

    /// Phrase without the replacement marker → nothing to repair.
    func testMissingMarkerReturnsEmpty() async {
        let phrase = (abandon11 + ["about"]).joined(separator: " ")
        let result = await PhraseRepairEngine.findPotentialWords(
            passphrase: phrase,
            replacement: "zzzz",
            language: nil,
            useDistanceAsBackup: true,
            dependencies: makeDependencies(existing: ["ADDR-about"]),
            progress: neverStop
        )
        XCTAssertTrue(result.isEmpty)
    }

    /// `findLastPotentialWords` pads an 11-word input with one "x" and
    /// routes into the single-missing path (on-chain only).
    func testFindLastWordPadsAndConfirmsOnChain() async {
        let phrase = abandon11.joined(separator: " ")
        let result = await PhraseRepairEngine.findLastPotentialWords(
            passphrase: phrase,
            dependencies: makeDependencies(existing: ["ADDR-about"]),
            progress: neverStop
        )
        XCTAssertEqual(result, ["about": 0])
    }

    /// Non-derivable candidates (today: non-English phrases through the
    /// English-hardcoded FFI) still reach the distance backup (deviation 5).
    func testDerivationFailureStillAllowsDistanceBackup() async {
        let phrase = (abandon11 + ["abouz"]).joined(separator: " ")
        let result = await PhraseRepairEngine.findPotentialWords(
            passphrase: phrase,
            replacement: "abouz",
            language: nil,
            useDistanceAsBackup: true,
            dependencies: makeDependencies(existing: [], derive: { _ in nil }),
            progress: neverStop
        )
        XCTAssertEqual(result["about"], 1)
    }
}

// MARK: - InsightClient (stubbed transport)

final class InsightClientTests: XCTestCase {

    private func makeClient() -> InsightClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return InsightClient(session: URLSession(configuration: configuration))
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testRequestShape() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString,
                           "https://insight.dash.org/insight-api/addrs/txs")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"),
                           "application/x-www-form-urlencoded")
            XCTAssertEqual(MockURLProtocol.bodyString(of: request), "addrs=Xaaa,Xbbb")
            return (200, Data(#"{"items": []}"#.utf8))
        }
        let existing = try await makeClient().findExistingAddresses(["Xaaa", "Xbbb"])
        XCTAssertTrue(existing.isEmpty)
    }

    func testMatchesViaVin() async throws {
        MockURLProtocol.handler = { _ in
            (200, Data(#"{"items": [{"vin": [{"addr": "Xaaa"}], "vout": []}]}"#.utf8))
        }
        let existing = try await makeClient().findExistingAddresses(["Xaaa", "Xbbb"])
        XCTAssertEqual(existing, ["Xaaa"])
    }

    func testMatchesViaVout() async throws {
        MockURLProtocol.handler = { _ in
            (200, Data(#"{"items": [{"vout": [{"scriptPubKey": {"addresses": ["Xbbb", "Xzzz"]}}]}]}"#.utf8))
        }
        let existing = try await makeClient().findExistingAddresses(["Xaaa", "Xbbb"])
        XCTAssertEqual(existing, ["Xbbb"])
    }

    func testMissingItemsThrows() async {
        MockURLProtocol.handler = { _ in (200, Data(#"{"unexpected": true}"#.utf8)) }
        do {
            _ = try await makeClient().findExistingAddresses(["Xaaa"])
            XCTFail("expected invalidResponse")
        } catch {}
    }

    func testHTTPErrorThrows() async {
        MockURLProtocol.handler = { _ in (500, Data()) }
        do {
            _ = try await makeClient().findExistingAddresses(["Xaaa"])
            XCTFail("expected invalidResponse")
        } catch {}
    }

    func testEmptyInputSkipsNetwork() async throws {
        MockURLProtocol.handler = { _ in
            XCTFail("no request expected for empty input")
            return (200, Data(#"{"items": []}"#.utf8))
        }
        let existing = try await makeClient().findExistingAddresses([])
        XCTAssertTrue(existing.isEmpty)
    }
}

// MARK: - MockURLProtocol

/// Minimal URLProtocol stub (none exists in this test target yet).
/// `handler` returns (statusCode, body); the request body of a data-task
/// POST surfaces through `httpBodyStream`, hence the helper.
final class MockURLProtocol: URLProtocol {

    static var handler: ((URLRequest) -> (Int, Data))?

    static func bodyString(of request: URLRequest) -> String? {
        if let body = request.httpBody {
            return String(data: body, encoding: .utf8)
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return String(data: data, encoding: .utf8)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let (statusCode, data) = handler(request)
        let response = HTTPURLResponse(url: request.url ?? URL(string: "https://insight.dash.org")!,
                                       statusCode: statusCode,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
