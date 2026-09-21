import XCTest
#if canImport(dashpay)
@testable import dashpay
#elseif canImport(dashwallet)
@testable import dashwallet
#else
@testable import WalletPreparationHarness
#endif

final class WalletPreparationFailureTests: XCTestCase {
    func testDiagnosticsExcludeDescriptionsPathsStoredValuesAndUnknownDomains() {
        let secret = "wallet-secret-sensitive-value"
        let underlying = NSError(domain: secret, code: 7, userInfo: [NSLocalizedDescriptionKey: secret])
        let error = NSError(domain: NSCocoaErrorDomain, code: 134100, userInfo: [
            NSLocalizedDescriptionKey: secret,
            NSFilePathErrorKey: "/private/\(secret)/wallet.sqlite",
            "storedObject": secret,
            NSUnderlyingErrorKey: underlying
        ])
        let failure = WalletPreparationFailure(error: error, now: Date(timeIntervalSince1970: 0))
        let report = failure.diagnosticReport(appVersion: "1.2 (3)", systemVersion: "iOS 26")
        XCTAssertFalse(report.contains(secret))
        XCTAssertFalse(failure.message.contains(secret))
        XCTAssertEqual(failure.codes, ["NSCocoaErrorDomain:134100", "OtherError:7"])
        XCTAssertTrue(report.contains("1.2 (3)"))
        XCTAssertTrue(report.contains("1970-01-01T00:00:00Z"))
    }

    func testDiskFullIsFoundInsideDetailedCoreDataErrors() {
        let storage = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
        let detailed = NSError(domain: NSCocoaErrorDomain, code: 134110, userInfo: [NSUnderlyingErrorKey: storage])
        let error = NSError(domain: NSCocoaErrorDomain, code: 134100, userInfo: ["NSDetailedErrors": [detailed]])
        XCTAssertEqual(WalletPreparationFailure(error: error).kind, .storage)
        XCTAssertEqual(WalletPreparationFailure(error: NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)).kind, .storage)
        XCTAssertEqual(WalletPreparationFailure(error: NSError(domain: "NSSQLiteErrorDomain", code: 13)).kind, .storage)
        XCTAssertEqual(WalletPreparationFailure(error: NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))).kind, .database)
    }

    func testLegacySpaceHintRequiresKnownDomainAndExactMessageShape() {
        let message = "Legacy database migration needs approximately 2 GB of free space; 1 GB is available. Free device storage and retry. The original database has not been replaced."
        let recognized = NSError(domain: "SwiftDashSDK.DashLegacyStoreSQLite.Failure", code: 2,
                                 userInfo: [NSLocalizedDescriptionKey: message])
        XCTAssertEqual(WalletPreparationFailure(error: recognized).kind, .storage)
        let unrelated = NSError(domain: "Unknown", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
        XCTAssertEqual(WalletPreparationFailure(error: unrelated).kind, .database)
    }

    func testErrorTraversalIsBoundedAndDeduplicatesSharedUnderlyingError() {
        let child = NSError(domain: NSCocoaErrorDomain, code: 1)
        let root = NSError(domain: NSCocoaErrorDomain, code: 2, userInfo: [
            NSUnderlyingErrorKey: child, "NSDetailedErrors": [child, child]
        ])
        XCTAssertEqual(WalletPreparationFailure(error: root).codes.count, 2)

        var nested = child
        for code in 2...100 {
            nested = NSError(domain: NSCocoaErrorDomain, code: code, userInfo: [NSUnderlyingErrorKey: nested])
        }
        XCTAssertEqual(WalletPreparationFailure(error: nested).codes.count, 8)
    }
}
