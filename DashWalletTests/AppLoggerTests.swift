//
//  AppLoggerTests.swift
//  DashWalletTests
//
//  What an `AppLogger` line puts into the exported file log: numbers and
//  Bool as is, other values only when marked public, errors as type and
//  code only.
//

import XCTest
@testable import dashpay

private enum SampleError: Error {
    case failed(path: String)
}

final class AppLoggerTests: XCTestCase {
    func testLiteralIsKept() {
        let message: AppLogMessage = "plain line"
        XCTAssertEqual(message.text, "plain line")
    }

    func testNumbersAndBoolArePublicByDefault() {
        let count = 3
        let fee: UInt64 = 226
        let ratio = 0.5
        let done = true
        let message: AppLogMessage = "count=\(count) fee=\(fee) ratio=\(ratio) done=\(done)"
        XCTAssertEqual(message.text, "count=3 fee=226 ratio=0.5 done=true")
    }

    func testStringIsPrivateByDefault() {
        let address = "yXabc"
        let message: AppLogMessage = "to \(address)"
        XCTAssertEqual(message.text, "to <private>")
    }

    func testOptionalIsPrivateByDefault() {
        let name: String? = "alice"
        let message: AppLogMessage = "name=\(name)"
        XCTAssertEqual(message.text, "name=<private>")
    }

    func testPublicStringIsKept() {
        let network = "testnet"
        let message: AppLogMessage = "on \(network, privacy: .public)"
        XCTAssertEqual(message.text, "on testnet")
    }

    func testPrivateNumberIsRedacted() {
        let balance = 150_000
        let message: AppLogMessage = "balance=\(balance, privacy: .private)"
        XCTAssertEqual(message.text, "balance=<private>")
    }

    func testErrorIsWrittenAsTypeAndCodeOnly() {
        let error: Error = SampleError.failed(path: "/var/mobile/secret.sqlite")
        let message: AppLogMessage = "failed: \(error)"
        XCTAssertFalse(message.text.contains("secret"))
        XCTAssertEqual(message.text, "failed: \(AppLogMessage.errorSummary(error))")
        XCTAssertTrue(message.text.hasPrefix("failed: SampleError.failed "))
    }

    func testNSErrorIsWrittenAsDomainAndCode() {
        let error = NSError(domain: NSCocoaErrorDomain, code: 134_110,
                            userInfo: [NSFilePathErrorKey: "/var/mobile/secret.sqlite"])
        let message: AppLogMessage = "\(error)"
        XCTAssertEqual(message.text, "NSError NSCocoaErrorDomain #134110")
    }

    func testWrappedErrorsAreSummarizedToo() {
        enum Envelope: Error { case transferFailed(Error) }
        let error: Error = Envelope.transferFailed(SampleError.failed(path: "/var/mobile/secret"))
        let summary = AppLogMessage.errorSummary(error)
        XCTAssertTrue(summary.hasPrefix("Envelope.transferFailed "))
        XCTAssertTrue(summary.contains(" ← SampleError.failed "))
        XCTAssertFalse(summary.contains("secret"))
    }

    func testUnderlyingNSErrorIsSummarizedToo() {
        let underlying = NSError(domain: NSPOSIXErrorDomain, code: 28)
        let error = NSError(domain: NSCocoaErrorDomain, code: 134_110,
                            userInfo: [NSUnderlyingErrorKey: underlying])
        XCTAssertEqual(AppLogMessage.errorSummary(error),
                       "NSError NSCocoaErrorDomain #134110 ← NSError NSPOSIXErrorDomain #28")
    }

    func testCaseNameSkipsPayloadAndCustomDescriptions() {
        enum Plain { case idle, failed(String) }
        enum Described: CustomStringConvertible {
            case secret
            var description: String { "leaked" }
        }
        XCTAssertEqual(AppLogMessage.caseName(of: Plain.idle), "idle")
        XCTAssertEqual(AppLogMessage.caseName(of: Plain.failed("/var/mobile/x")), "failed")
        XCTAssertNil(AppLogMessage.caseName(of: Described.secret))
        XCTAssertNil(AppLogMessage.caseName(of: "not an enum"))
    }

    func testErrorLineIsInTheExportedFileWhenTheCallReturns() throws {
        let marker = UUID().uuidString
        AppLogger(category: "app-logger-test").error("export check \(marker, privacy: .public)")

        let files = DWLogger.sharedInstance().logFiles()
        let contents = try files.map { try String(contentsOf: $0, encoding: .utf8) }
        let line = contents.joined().split(separator: "\n").first { $0.contains(marker) }
        XCTAssertNotNil(line)
        XCTAssertTrue(line?.contains("app-logger-test - ERROR export check") ?? false)
    }

    func testPrivateErrorIsRedacted() {
        let error: Error = SampleError.failed(path: "x")
        let message: AppLogMessage = "\(error, privacy: .private)"
        XCTAssertEqual(message.text, "<private>")
    }
}
