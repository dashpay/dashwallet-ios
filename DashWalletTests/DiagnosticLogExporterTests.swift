//
//  DiagnosticLogExporterTests.swift
//  DashWalletTests
//
//  Behavioral tests for the pure selection policies in
//  `DiagnosticLogExporter` — which SDK log sessions and which app log
//  files go into a diagnostic export.
//
//  Session-policy invariants (mirroring the SwiftDashSDK example
//  app's `LogExporterSelectionTests`, the source of the ported
//  policy):
//  - the caller-provided current session is authoritative: always
//    first and always included, regardless of how its timestamp sorts
//    against other directories and regardless of the byte cap;
//  - older sessions fill remaining slots newest-first, subject to the
//    session-count cap and the total-bytes cap;
//  - the walk stops at the first over-budget session instead of
//    skipping past it, so the archive is a contiguous run of the most
//    recent history;
//  - with no known current session, the newest directory on disk
//    still gets exported.
//
//  App-log invariants: newest-first by modification date under a byte
//  cap; the newest file is always included even when it alone exceeds
//  the cap.
//
//  NOTE: the DashWalletTests bundle is pre-existing broken (see
//  DWRegistrationPhaseAdapterTests). These are compile-ready
//  documentation-as-tests until the bundle is repaired.
//

import XCTest
@testable import dashwallet

final class DiagnosticLogExporterTests: XCTestCase {
    private func candidate(_ stamp: String, bytes: UInt64) -> DiagnosticLogExporter.SessionCandidate {
        DiagnosticLogExporter.SessionCandidate(
            url: URL(fileURLWithPath: "/logs/\(stamp)", isDirectory: true),
            bytes: bytes
        )
    }

    // MARK: - SDK session selection

    func testCurrentSessionIsFirstEvenWhenOlderStampedThanOthers() {
        // A stale future-dated directory sorts lexicographically after
        // the real current session. It must not displace it.
        let current = candidate("2026-07-15T10-00-00Z", bytes: 100)
        let futureStale = candidate("2027-01-01T00-00-00Z", bytes: 100)
        let previous = candidate("2026-07-14T09-00-00Z", bytes: 100)

        let selected = DiagnosticLogExporter.selectSessions(
            current: current,
            others: [previous, futureStale]
        )

        XCTAssertEqual(selected.first, current)
        XCTAssertEqual(selected.count, 3)
        XCTAssertEqual(selected[1], futureStale)
        XCTAssertEqual(selected[2], previous)
    }

    func testSessionCountCap() {
        let current = candidate("2026-07-15T10-00-00Z", bytes: 1)
        let others = (1...5).map {
            candidate("2026-07-10T0\($0)-00-00Z", bytes: 1)
        }

        let selected = DiagnosticLogExporter.selectSessions(current: current, others: others)

        XCTAssertEqual(selected.count, DiagnosticLogExporter.maxSDKSessions)
        XCTAssertEqual(selected.first, current)
        XCTAssertEqual(
            selected.dropFirst().map { $0.url.lastPathComponent },
            ["2026-07-10T05-00-00Z", "2026-07-10T04-00-00Z"]
        )
    }

    func testByteCapStopsAtFirstOverBudgetSession() {
        let current = candidate("2026-07-15T10-00-00Z", bytes: 4)
        // The big middle session breaches the cap; the walk must stop
        // there, NOT skip past it to the small older one.
        let big = candidate("2026-07-14T09-00-00Z", bytes: 100)
        let small = candidate("2026-07-13T08-00-00Z", bytes: 1)

        let selected = DiagnosticLogExporter.selectSessions(
            current: current,
            others: [big, small],
            maxTotalBytes: 10
        )

        XCTAssertEqual(selected, [current])
    }

    func testCurrentAlwaysIncludedEvenWhenAloneOverBudget() {
        let current = candidate("2026-07-15T10-00-00Z", bytes: 1_000)

        let selected = DiagnosticLogExporter.selectSessions(
            current: current,
            others: [],
            maxTotalBytes: 10
        )

        XCTAssertEqual(selected, [current])
    }

    func testNoCurrentSessionFallsBackToNewestOnDisk() {
        let older = candidate("2026-07-13T08-00-00Z", bytes: 1)
        let newest = candidate("2026-07-14T09-00-00Z", bytes: 1)

        let selected = DiagnosticLogExporter.selectSessions(
            current: nil,
            others: [older, newest]
        )

        XCTAssertEqual(selected.first, newest)
        XCTAssertEqual(selected.count, 2)
    }

    // MARK: - App-log selection

    /// Temp files with controlled sizes + modification dates —
    /// `selectAppLogs` reads both from the filesystem.
    private func makeTempLog(name: String, bytes: Int, modified: Date) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiagnosticLogExporterTests", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try Data(count: bytes).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: modified], ofItemAtPath: url.path)
        return url
    }

    func testAppLogsSelectedNewestFirstUnderByteCap() throws {
        let newest = try makeTempLog(name: "c.log", bytes: 4, modified: Date(timeIntervalSince1970: 300))
        let middle = try makeTempLog(name: "b.log", bytes: 4, modified: Date(timeIntervalSince1970: 200))
        let oldest = try makeTempLog(name: "a.log", bytes: 4, modified: Date(timeIntervalSince1970: 100))

        let selected = DiagnosticLogExporter.selectAppLogs(
            [oldest, newest, middle],
            maxTotalBytes: 8
        )

        XCTAssertEqual(selected, [newest, middle])
    }

    func testNewestAppLogIncludedEvenWhenAloneOverCap() throws {
        let huge = try makeTempLog(name: "huge.log", bytes: 64, modified: Date(timeIntervalSince1970: 300))
        let old = try makeTempLog(name: "old.log", bytes: 1, modified: Date(timeIntervalSince1970: 100))

        let selected = DiagnosticLogExporter.selectAppLogs(
            [old, huge],
            maxTotalBytes: 10
        )

        XCTAssertEqual(selected, [huge])
    }
}
