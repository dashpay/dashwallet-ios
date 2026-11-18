//
//  AppLoggerTests.swift
//  DashWalletTests
//
//  What an `AppLogger` line puts into the exported file log: numbers and
//  Bool as is, other values only when marked public, errors as type and
//  code only.
//

import SwiftDashSDK
import XCTest
@testable import dashpay

private enum SampleError: Error {
    case failed(path: String)
}

/// Records the flag of every log message that holds `marker`, in order.
private final class CapturingLogger: DDAbstractLogger, @unchecked Sendable {
    private let marker: String
    private let lock = NSLock()
    private var captured: [DDLogFlag] = []

    init(marker: String) {
        self.marker = marker
        super.init()
    }

    var flags: [DDLogFlag] {
        lock.lock()
        defer { lock.unlock() }
        return captured
    }

    @objc(logMessage:)
    func log(message logMessage: DDLogMessage) {
        guard logMessage.message.contains(marker) else { return }
        lock.lock()
        captured.append(logMessage.flag)
        lock.unlock()
    }
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

    // AC-02, AC-08: the file has no level column, so warning, error and
    // fault lines carry a text tag, written once; a fault is in the file
    // when the call returns.
    func testEachLevelIsWrittenOnceWithItsTag() throws {
        let marker = UUID().uuidString
        let logger = AppLogger(category: "app-logger-test")
        logger.info("info \(marker, privacy: .public)")
        logger.notice("notice \(marker, privacy: .public)")
        logger.warning("warning \(marker, privacy: .public)")
        logger.error("error \(marker, privacy: .public)")
        logger.fault("fault \(marker, privacy: .public)")

        // Read right after the fault call, with no flush line in between.
        let files = DWLogger.sharedInstance().logFiles()
        let lines = try files.map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n").split(separator: "\n").filter { $0.contains(marker) }
        for expected in [
            "app-logger-test - info \(marker)",
            "app-logger-test - notice \(marker)",
            "app-logger-test - WARNING warning \(marker)",
            "app-logger-test - ERROR error \(marker)",
            "app-logger-test - FAULT fault \(marker)",
        ] {
            XCTAssertEqual(lines.filter { $0.hasSuffix(expected) }.count, 1, "\(expected) in \(lines)")
        }
        XCTAssertEqual(lines.count, 5, "\(lines)")
    }

    // AC-06: debug lines exist in developer builds only. The log level is a
    // compile-time constant of DWLogger.h, so the release side is checked in
    // the source: the release level is Info, and a debug call goes through
    // CocoaLumberjack's debug flag, which Info does not include.
    func testDebugLineIsWrittenInThisDebugBuildOnly() throws {
        let marker = UUID().uuidString
        AppLogger(category: "app-logger-test").debug("debug \(marker, privacy: .public)")
        XCTAssertEqual(try exportedLines(matching: marker).count, 1)

        let header = try sourceText("DashWallet/Sources/Infrastructure/DWLogger.h")
        let release = try XCTUnwrap(
            header.range(of: "#else\nstatic const DDLogLevel ddLogLevel = DDLogLevelInfo;"))
        XCTAssertNotNil(header.range(
            of: "#ifdef DEBUG\nstatic const DDLogLevel ddLogLevel", range: header.startIndex..<release.lowerBound))
        XCTAssertTrue(header.contains("#define DWLogDebug(className, frmt, ...) DDLogDebug("))
        let implementation = try sourceText("DashWallet/Sources/Infrastructure/DWLogger.m")
        XCTAssertTrue(implementation.contains(
            "+ (void)logDebug:(NSString *)message className:(NSString *)className {\n    DWLogDebug("))
    }

    // AC-02, AC-06: each level reaches CocoaLumberjack with its own flag. A
    // debug line carries the debug flag, which the release level (Info, see
    // above) leaves out; written through the info flag it would be in a
    // release build's file.
    func testEachLevelReachesTheLogWithItsFlag() {
        let marker = UUID().uuidString
        let capture = CapturingLogger(marker: marker)
        DDLog.add(capture, with: .all)
        defer { DDLog.remove(capture) }

        let logger = AppLogger(category: "app-logger-test")
        logger.debug("debug \(marker, privacy: .public)")
        logger.info("info \(marker, privacy: .public)")
        logger.notice("notice \(marker, privacy: .public)")
        logger.warning("warning \(marker, privacy: .public)")
        logger.error("error \(marker, privacy: .public)")
        logger.fault("fault \(marker, privacy: .public)")
        DDLog.flushLog()

        XCTAssertEqual(capture.flags, [.debug, .info, .info, .warning, .error, .error])
    }

    // AC-03: a consensus rejection adds its code and kind, never Platform's text.
    func testConsensusRejectionAddsItsCodeAndKind() {
        let error = PlatformWalletError.consensusRejection(
            PlatformConsensusError(code: 10534, kind: .basic), "asset lock transaction has too many inputs")
        let summary = AppLogMessage.errorSummary(error)
        XCTAssertTrue(summary.contains("consensus code=10534 kind=basic"), summary)
        XCTAssertFalse(summary.contains("asset lock transaction"), summary)
    }

    // AC-03: the error and up to three wrapped errors; the fourth is dropped.
    func testWrappedChainDeeperThanThreeIsCutAtThree() {
        enum Envelope: Error { case wrap(Error) }
        let innermost = SampleError.failed(path: "x")
        let error: Error = Envelope.wrap(Envelope.wrap(Envelope.wrap(Envelope.wrap(innermost))))
        let summary = AppLogMessage.errorSummary(error)
        XCTAssertEqual(summary.components(separatedBy: " ← ").count, 4, summary)
        XCTAssertFalse(summary.contains("SampleError"), summary)
    }

    // AC-04: the Error summary keeps only the case name, so two keychain
    // read failures are told apart by the status number the KEYMIG lines add.
    func testKeyMigrationKeychainFailuresShowTheirStatus() {
        typealias CleanupError = SwiftDashSDKKeyMigrator.LegacyMnemonicCleanupError
        let notFound: Error = CleanupError.keychainRead(errSecItemNotFound)
        let locked: Error = CleanupError.keychainRead(errSecInteractionNotAllowed)

        XCTAssertEqual(
            AppLogMessage.errorSummary(notFound), AppLogMessage.errorSummary(locked))
        XCTAssertEqual(SwiftDashSDKKeyMigrator.keychainStatus(of: notFound), "-25300")
        XCTAssertEqual(SwiftDashSDKKeyMigrator.keychainStatus(of: locked), "-25308")

        // The line itself, as both KEYMIG enumeration sites write it.
        let summary = AppLogMessage.errorSummary(notFound)
        XCTAssertEqual(
            SwiftDashSDKKeyMigrator.enumerationFailedLine(notFound).text,
            "🔑 KEYMIG :: DashSync mnemonic enumeration failed: \(summary) status=-25300")
        XCTAssertEqual(
            SwiftDashSDKKeyMigrator.enumerationFailedLine(locked, during: "launch probe").text,
            "🔑 KEYMIG :: DashSync mnemonic enumeration failed during launch probe: \(summary) status=-25308")
    }

    func testKeyMigrationNonKeychainFailureHasNoStatus() {
        typealias CleanupError = SwiftDashSDKKeyMigrator.LegacyMnemonicCleanupError
        XCTAssertEqual(SwiftDashSDKKeyMigrator.keychainStatus(of: CleanupError.mnemonicRead), "-")
        XCTAssertEqual(SwiftDashSDKKeyMigrator.keychainStatus(of: SampleError.failed(path: "x")), "-")
    }

    // AC-05: a Financial amount (a balance or a payment amount) is written as
    // <private>; fees and counts stay visible.

    #if DASHPAY
    func testPayToContactAmountIsRedactedInTheExportedFile() async throws {
        // Unique per run: the simulator keeps the log files between runs.
        let amount = UInt64.random(in: 100_000_000_000...999_999_999_999)
        let contactId = Data(UUID().uuidString.utf8)
        // A contact with an unknown earlier outcome is refused right after
        // the line is written, before any PIN prompt.
        WalletSendService.shared.unknownContactPaymentOutcomes.record(contactIdentityId: contactId)

        try await assertRedactedInExport(":: pay-to-contact preparing — <private> duffs", amounts: [amount]) {
            _ = try? await WalletSendService.shared.prepareContactPayment(
                contactIdentityId: contactId, amount: amount)
        }
        XCTAssertFalse(try exportedLines(matching: "pay-to-contact preparing").contains { $0.contains(String(amount)) })
    }
    #endif

    /// Lines no unit test can drive without a new seam (SDK host, SPV
    /// callbacks): checked in the source instead (owner decision, 2026-11-18).
    func testWalletAndSendAmountsAreMarkedPrivate() throws {
        let send = "DashWallet/Sources/Models/Transactions/WalletSendService.swift"
        let state = "DashWallet/Sources/Infrastructure/SwiftDashSDK/SwiftDashSDKWalletState.swift"
        try assertPrivate(
            "DashWallet/Sources/Infrastructure/SwiftDashSDK/SwiftDashSDKCoinJoinBalanceReader.swift",
            line: "CJBAL :: coinjoin spendable balance", values: ["total"])
        try assertPrivate(send, line: "preparing CoinJoin sweep", values: ["amount", "Double(amount) / 1e8"])
        try assertPrivate(send, line: "sweep returned no transactions for", values: ["amount"])
        try assertPrivate(send, line: "post-sweep CoinJoin balance", values: ["post", "amount"])
        try assertPrivate(
            "DashWallet/Sources/Infrastructure/SwiftDashSDK/Identity/DWCurrentUserIdentityInfo.swift",
            line: "refreshed identity balance", values: ["balance"])
        try assertPrivate(state, line: "platformPaymentCredits=\\(", values: ["total"])
        try assertPrivate(state, line: "pooledSpendableDuffs=\\(", values: ["duffs"])
        try assertPrivate(state, line: "coinJoinBalanceDuffs=\\(", values: ["duffs"])

        let watch = try sourceLine(
            "DashWallet/Sources/AppleWatch/DWPhoneWCSessionManager.m", containing: "watch requested a qr code")
        XCTAssertFalse(watch.contains("amount"), watch)
    }

    /// Each route writes its line, then stops at the missing SDK wallet in
    /// the test host or, when an earlier test left one there, at the
    /// authorizer, which always refuses: no route can spend, and none waits
    /// for a PIN prompt.
    @MainActor
    func testShieldedTransferAmountsAreRedactedInTheExportedFile() async throws {
        let suiteName = "AppLoggerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        func coordinator() -> ShieldedTransferCoordinator {
            ShieldedTransferCoordinator(
                failureStore: AssetLockFailureStore(defaults: defaults),
                authorize: { throw DWIdentityAuthorizer.AuthError.failed })
        }
        func randomAmount() -> UInt64 { UInt64.random(in: 100_000_000_000...999_999_999_999) }

        let shield = randomAmount()
        try await assertRedactedInExport(
            ":: shield route amount=<private> credits external=false", amounts: [shield]) {
            await coordinator().performShield(amountCredits: shield)
        }
        let withdraw = randomAmount()
        try await assertRedactedInExport(
            ":: withdraw route amount=<private> credits external=false", amounts: [withdraw]) {
            await coordinator().performWithdraw(amountCredits: withdraw)
        }
        let unshield = randomAmount()
        try await assertRedactedInExport(
            ":: unshield route amount=<private> credits external=false", amounts: [unshield]) {
            await coordinator().performUnshield(amountCredits: unshield)
        }
        let transfer = randomAmount()
        try await assertRedactedInExport(":: shielded→shielded send amount=<private> credits", amounts: [transfer]) {
            await coordinator().performShieldedTransfer(
                amountCredits: transfer, recipientRaw43: Data(repeating: 1, count: 43))
        }
        let recipient = randomAmount()
        let lock = recipient + 1_000_000
        try await assertRedactedInExport(
            ":: core→platform fund route recipient=<private> lock=<private>", amounts: [recipient, lock]) {
            await coordinator().performFundPlatform(recipientAmountDuffs: recipient, lockValueDuffs: lock)
        }
        let assetLock = randomAmount()
        try await assertRedactedInExport(":: asset-lock route funding=bip44 external=false", amounts: [assetLock]) {
            await coordinator().performAssetLock(funding: .bip44(recipientAmountDuffs: assetLock))
        }
    }

    /// Lines past an SDK wallet, a Platform address sync or an invitation
    /// fetch in the test host.
    func testPlatformCoinJoinAndInvitationAmountsAreMarkedPrivate() throws {
        let platform = "DashWallet/Sources/Infrastructure/SwiftDashSDK/PlatformAddressSyncCoordinator.swift"
        try assertPrivate(platform, line: "PLATFORM-SEND :: →", values: ["amount"])
        try assertPrivate(platform, line: "PLATFORM-WITHDRAW :: partial amount=", values: ["amountCredits"])
        try assertPrivate(platform, line: "PLATFORM-FUND :: core → platform recipient=",
                          values: ["recipientAmountDuffs", "lockValueDuffs"])
        try assertPrivate(
            "DashWallet/Sources/Models/CoinJoin/CoinJoinRecovery.swift",
            line: "CJRECOV :: sweep prompt deferred at", values: ["balanceDuffs"])
        try assertPrivate(
            "DashWallet/Sources/Infrastructure/SwiftDashSDK/Invitations/InvitationValidation.swift",
            line: "INVITE :: status amount=", values: ["status.amountDuffs"])
    }

    /// Written before the coordinator runs, so also for a name that is never
    /// registered (a cancelled PIN, an abandoned sheet): no username, requested
    /// or companion, may reach the export from these lines.
    func testRegistrationBridgeLinesWriteNoUsername() throws {
        let text = try sourceText(
            "DashWallet/Sources/Infrastructure/SwiftDashSDK/Identity/DWIdentityRegistrationBridge.swift")
        let lines = text.split(separator: "\n").filter { $0.contains("IDENT-BRIDGE ::") }
        XCTAssertGreaterThanOrEqual(lines.count, 5)
        for line in lines {
            for name in ["username", "temporary", "temporaryUsername"] {
                XCTAssertFalse(line.contains("\\(\(name), privacy: .public)"), String(line))
                XCTAssertFalse(line.contains("\\(\(name) ?? "), String(line))
            }
        }
    }

    /// The coordinator's entry lines also run before authorization (start,
    /// retry, purchase, a rejected pairing), so they write no name either
    /// (AC-10); its lines after authorization keep the label.
    func testRegistrationCoordinatorLinesBeforeAuthorizationWriteNoUsername() throws {
        let coordinator = "DashWallet/Sources/Infrastructure/SwiftDashSDK/Identity/DWIdentityRegistrationCoordinator.swift"
        for fragment in [
            "IDENT-COORD :: startCreateUsername", "IDENT-COORD :: invalid temporary username pairing",
            "IDENT-COORD :: retry", "IDENT-COORD :: startPurchaseUsername",
        ] {
            let line = try sourceLine(coordinator, containing: fragment)
            for name in ["username", "name", "temporaryUsername"] {
                XCTAssertFalse(line.contains("\\(\(name), privacy: .public)"), line)
                XCTAssertFalse(line.contains("\\(\(name) ?? "), line)
            }
        }
    }

    /// `logSweepBroadcast` already writes each accepted chunk's txid; the
    /// bookkeeping line only says how many were recorded.
    func testSweepRecordLineWritesTheCountOnly() throws {
        let line = try sourceLine(
            "DashWallet/Sources/Models/Transactions/WalletSendService.swift",
            containing: "sweep txid(s) in CoinJoinWithdrawalStore")
        XCTAssertFalse(line.contains("hexes"), line)
        XCTAssertFalse(line.contains("joined("), line)
    }

    /// Written only while an SDK wallet is bound, so a source check rather
    /// than an export test.
    func testAssetLockInputLineWritesNoAmount() throws {
        let line = try sourceLine(
            "DashWallet/Sources/Infrastructure/SwiftDashSDK/AssetLockInputPolicy.swift",
            containing: "ASSET-LOCK-INPUTS :: amount=")
        XCTAssertTrue(line.contains(#""<private>""#), line)
        XCTAssertFalse(line.contains("amountDuffs.map"), line)
        XCTAssertFalse(line.contains("String.init"), line)
    }

    /// The SPV and Platform address coordinators keep an English reason for
    /// their last error, which a failed network switch writes to the export.
    func testCoordinatorErrorLogReasonsHoldNoErrorText() throws {
        for path in [
            "DashWallet/Sources/Infrastructure/SwiftDashSDK/SwiftDashSDKSPVCoordinator.swift",
            "DashWallet/Sources/Infrastructure/SwiftDashSDK/PlatformAddressSyncCoordinator.swift",
        ] {
            let lines = try sourceText(path).components(separatedBy: "\n")
            var reasons: [String] = []
            for (index, line) in lines.enumerated() {
                guard let range = line.range(of: #"(\blog:|LogReason =)\s*"#, options: .regularExpression) else { continue }
                var reason = String(line[range.upperBound...])
                // The value can start on the next line.
                if reason.trimmingCharacters(in: .whitespaces).isEmpty, index + 1 < lines.count {
                    reason = lines[index + 1]
                }
                reasons.append(reason)
            }
            XCTAssertGreaterThan(reasons.count, 3, path)
            for reason in reasons {
                XCTAssertFalse(reason.contains("String(describing:"), "\(path): \(reason)")
                XCTAssertFalse(reason.contains("localizedDescription"), "\(path): \(reason)")
                XCTAssertFalse(reason.contains("errorMessage"), "\(path): \(reason)")
                // Only an Error summary may be interpolated: `\(error)` here
                // is plain string interpolation and writes the error's text.
                XCTAssertEqual(
                    reason.components(separatedBy: #"\("#).count,
                    reason.components(separatedBy: #"\(AppLogMessage.errorSummary("#).count,
                    "\(path): \(reason)")
            }
        }
    }

    /// Lines written after a PIN prompt or an SDK fee estimate.
    func testTransferWithdrawalAndPurchaseAmountsAreMarkedPrivate() throws {
        let shielded = "DashWallet/Sources/UI/Payments/InternalTransfer/Shielded/ShieldedTransferCoordinator.swift"
        try assertPrivate(shielded, line: "fee-on-top lock recipient=", values: ["recipientAmountDuffs", "lockDuffs"])
        try assertPrivate(shielded, line: "platform→core withdraw route full=", values: ["amountCredits"])
        try assertPrivate(shielded, line: "platform→platform send amount=", values: ["amountCredits"])
        try assertPrivate(
            "DashWallet/Sources/UI/Menu/Tools/Masternode Withdrawal/EvonodeWithdrawalViewModel.swift",
            line: "EVONODE :: withdrawing", values: ["credits"])
        try assertPrivate(
            "DashWallet/Sources/Infrastructure/SwiftDashSDK/UsernameMarketplaceService.swift",
            line: "MARKET :: purchased", values: ["expectedPriceCredits"])
    }

    /// Identity-registration lines keep the #1155 values except Financial
    /// amounts (AC-10 as narrowed by the owner, 2026-11-18); the coordinator
    /// needs a live identity to reach them.
    func testIdentityRegistrationAmountsAreMarkedPrivate() throws {
        let coordinator = "DashWallet/Sources/Infrastructure/SwiftDashSDK/Identity/DWIdentityRegistrationCoordinator.swift"
        try assertPrivate(coordinator, line: ") identityFundingDuffs=", values: ["requiredIdentityFundingDuffs"])
        try assertPrivate(coordinator, line: "IDENT-COORD :: PP inputs=", values: ["targetCredits"])
        try assertPrivate(
            coordinator, line: "IDENT-COORD :: existing identity requiredCredits=",
            values: ["requiredCredits", "heldCredits", "topUpDuffs"])
        // Whether a top-up was authorized is not an amount: `none` stays visible.
        let existing = try sourceLine(coordinator, containing: "IDENT-COORD :: existing identity requiredCredits=")
        XCTAssertTrue(
            existing.contains(
                #"authorized=\(plan.authorizedDuffs == nil ? "none" : AppLogMessage.redacted, privacy: .public)"#),
            existing)
        try assertPrivate(coordinator, line: "IDENT-COORD :: shielded create denomination=", values: ["denomination"])
        try assertPrivate(coordinator, line: "IDENT-COORD :: existing identity topped up by", values: ["topUpDuffs"])
        try assertPrivate(coordinator, line: "IDENT-COORD :: startPurchaseUsername", values: ["priceCredits"])
        try assertPrivate(coordinator, line: "IDENT-COORD :: purchase top-up shortfallDuffs=", values: ["shortfallDuffs"])
        try assertPrivate(coordinator, line: "IDENT-COORD :: purchased", values: ["priceCredits"])
    }

    // AC-05: across every app log line, a public wallet, identity or contact
    // id is an Identifier prefix, and an address, a destination, a profile
    // field or the invitation scope key is never public (a masternode's
    // `displayName` is its type and index). The lines sit past
    // an SDK wallet or identity in the test host, so the rule is checked in
    // the source.
    func testIdsArePrefixesAndAddressesProfileFieldsAndScopeKeyAreNeverPublic() throws {
        let publicValue = try NSRegularExpression(
            pattern: #"\\\(((?:[^()]|\((?:[^()]|\([^()]*\))*\))*?), privacy: \.public\)"#)
        func matches(_ pattern: String, _ text: String) -> Bool {
            text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        var violations: [String] = []
        for (path, text) in try appSources() {
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let line = String(line)
                let range = NSRange(line.startIndex..., in: line)
                let values = publicValue.matches(in: line, range: range)
                    .compactMap { Range($0.range(at: 1), in: line).map { String(line[$0]) } }
                for value in values {
                    let isFlagOrCount = matches(#"count|isEmpty|!= nil|== nil"#, value)
                    let isId = matches(#"wallet_?id|identity_?id|contact_?id|recipientId|base58"#, value)
                    let isSensitive = matches(
                        #"address(?!Index)|destination|storageKey|(?<!node\.)displayName|publicMessage|avatarUrl"#, value)
                    if isId, !value.contains("prefix("), !isFlagOrCount {
                        violations.append("\(path):\(index + 1) full id: \(value)")
                    }
                    if isSensitive, !isFlagOrCount {
                        violations.append("\(path):\(index + 1) public: \(value)")
                    }
                }
            }
        }
        XCTAssertEqual(violations, [])
    }

    // AC-10: the line families support searches by tag keep it; lines that
    // had no tag on develop (955db4018) are listed.
    func testMarkerLineFamiliesKeepTheirTags() throws {
        struct Family {
            let path: String
            let tags: [String]
            var untagged: [String] = []
        }
        let sdk = "DashWallet/Sources/Infrastructure/SwiftDashSDK/"
        let families = [
            Family(path: sdk + "Identity/DWIdentityRegistrationCoordinator.swift", tags: ["🪪 IDENT-COORD ::"],
                   untagged: ["DPNS completed in original context", "Legacy contest ownership is still unknown"]),
            Family(path: sdk + "SwiftDashSDKTransactionSender.swift", tags: ["💸 TXSEND ::"]),
            Family(path: sdk + "SwiftDashSDKSPVCoordinator.swift", tags: ["🛰️ SPVCOORD ::", "🛰️ SPV-RESYNC ::"]),
            Family(path: sdk + "SwiftDashSDKKeyMigrator.swift", tags: ["🔑 KEYMIG ::"]),
        ]
        let call = try NSRegularExpression(pattern: #"\b[Ll]ogger\.(?:info|debug|notice|warning|error|fault)\(\s*""#)
        for family in families {
            let text = try sourceText(family.path)
            let starts = call.matches(in: text, range: NSRange(text.startIndex..., in: text))
                .compactMap { Range($0.range, in: text).map { String(text[$0.upperBound...].prefix(60)) } }
            XCTAssertGreaterThan(starts.count, 10, family.path)
            let offTag = starts.filter { start in
                !family.tags.contains { start.hasPrefix($0) } && !family.untagged.contains { start.hasPrefix($0) }
            }
            XCTAssertEqual(offTag, [], family.path)
        }
        // Identity registration keeps the #1155 values that are not amounts.
        let identity = try sourceText(families[0].path)
        XCTAssertTrue(identity.contains(#"IDENT-COORD :: contested=\(isContestedSubmission, privacy: .public) "#
            + #"label=\(username, privacy: .public)""#))
        XCTAssertTrue(identity.contains(#"source=\(plan.source.logLabel, privacy: .public)""#))
    }

    // AC-11: a refused or unconfirmed broadcast keeps the full txid and the
    // network's reason as returned.
    func testBroadcastLinesKeepTheFullTxidAndTheReason() {
        let txid = String(repeating: "ab", count: 32)
        let hash = String(repeating: "cd", count: 32)
        let reason = "mandatory-script-verify-flag-failed (Signature must be zero for failed CHECK(MULTI)SIG operation)"
        XCTAssertEqual(
            SwiftDashSDKTransactionSender.broadcastLine(.rejected(txid: txid, reason: reason), displayHash: hash).text,
            "💸 TXSEND :: broadcast rejected — sdkTxid=\(txid) txHash=\(hash) reason=\(reason)")
        let unknown = CoreTransactionBroadcastOutcome.unknown(txid: txid, reason: "timeout")
        XCTAssertEqual(
            SwiftDashSDKTransactionSender.broadcastLine(unknown, displayHash: hash).text,
            "💸 TXSEND :: broadcast unknown — sdkTxid=\(txid) txHash=\(hash) reason=timeout")
        XCTAssertEqual(
            SwiftDashSDKTransactionSender.broadcastLine(.accepted(txid: txid), displayHash: hash).text,
            "💸 TXSEND :: broadcast accepted — sdkTxid=\(txid) txHash=\(hash)")
    }

    func testFeesAndFlagsStayVisible() throws {
        let line = try sourceLine(
            "DashWallet/Sources/Models/Transactions/WalletSendService.swift",
            containing: "pay-to-contact prepared, fee")
        XCTAssertTrue(line.contains("\\(payment.feeDuffs, privacy: .public)"), line)
        // `fullBalance` is the sweep-all flag, not an amount.
        let withdraw = try sourceLine(
            "DashWallet/Sources/UI/Payments/InternalTransfer/Shielded/ShieldedTransferCoordinator.swift",
            containing: "platform→core withdraw route full=")
        XCTAssertTrue(withdraw.contains("full=\\(fullBalance) "), withdraw)
    }

    // MARK: - Helpers

    /// Lines of the exported log files that contain `fragment`, read after a
    /// synchronous error line so every earlier line is in the file.
    private func exportedLines(matching fragment: String) throws -> [Substring] {
        AppLogger(category: "app-logger-test").error("flush \(UUID().uuidString, privacy: .public)")
        let files = DWLogger.sharedInstance().logFiles()
        let contents = try files.map { try String(contentsOf: $0, encoding: .utf8) }
        return contents.joined(separator: "\n").split(separator: "\n").filter { $0.contains(fragment) }
    }

    /// `run` writes exactly one `expected` line, and no
    /// exported line holds any of `amounts` (each is unique per run, so any
    /// line of the flow that wrote it shows up, not only `expected`).
    private func assertRedactedInExport(
        _ expected: String, amounts: [UInt64],
        file: StaticString = #filePath, line: UInt = #line,
        run: () async -> Void
    ) async throws {
        // Counted as written, not in the rolling files, where rotation can
        // drop an older matching line while `run` is going.
        let capture = CapturingLogger(marker: expected)
        DDLog.add(capture, with: .all)
        await run()
        DDLog.flushLog()
        DDLog.remove(capture)
        XCTAssertEqual(capture.flags.count, 1, expected, file: file, line: line)
        for amount in amounts {
            let leaks = try exportedLines(matching: String(amount))
            XCTAssertTrue(leaks.isEmpty, "\(amount) written: \(leaks)", file: file, line: line)
        }
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func sourceText(_ path: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(path), encoding: .utf8)
    }

    /// Every Swift file under `DashWallet/Sources`, by repository path.
    private func appSources() throws -> [(String, String)] {
        let sources = repositoryRoot.appendingPathComponent("DashWallet/Sources")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        XCTAssertGreaterThan(files.count, 100)
        return try files.map { url in
            (url.path.replacingOccurrences(of: repositoryRoot.path + "/", with: ""),
             try String(contentsOf: url, encoding: .utf8))
        }
    }

    /// The one line of a repository source file that contains `fragment`.
    private func sourceLine(_ path: String, containing fragment: String) throws -> String {
        let text = try sourceText(path)
        let matches = text.split(separator: "\n").filter { $0.contains(fragment) }
        XCTAssertEqual(matches.count, 1, "\(path): \(fragment)")
        return matches.first.map(String.init) ?? ""
    }

    private func assertPrivate(
        _ path: String, line fragment: String, values: [String],
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let source = try sourceLine(path, containing: fragment)
        for value in values {
            XCTAssertTrue(
                source.contains("\\(\(value), privacy: .private)"),
                "\(value) is not private: \(source)", file: file, line: line)
        }
    }
}
