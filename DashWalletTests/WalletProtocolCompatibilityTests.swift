import Foundation
import SwiftDashSDK
import XCTest
@testable import dashpay

@MainActor
final class WalletProtocolCompatibilityTests: XCTestCase {
    private let foreground = Notification.Name("test.willEnterForeground")

    private func info(_ newer: Bool = false) throws -> ProtocolVersionInfo {
        try JSONDecoder().decode(ProtocolVersionInfo.self, from: Data("""
            {"verifiedVersion":\(newer ? "16" : "null"),"effectiveVersion":14,
             "maximumSupportedVersion":15,"newerProtocolAvailable":\(newer)}
            """.utf8))
    }

    func testDecoderKeepsUnobservedDistinctAndPreservesRustVerdict() throws {
        XCTAssertNil(try info().verifiedVersion)
        let newer = try info(true)
        XCTAssertEqual(newer.verifiedVersion, 16)
        XCTAssertEqual(newer.effectiveVersion, 14)
        XCTAssertEqual(newer.maximumSupportedVersion, 15)
        XCTAssertTrue(newer.newerProtocolAvailable)
    }

    func testStartReturnsBeforeQueryAndConcurrentRefreshSharesIt() async throws {
        let controller = WalletProtocolCompatibilityController(foregroundNotification: foreground)
        let client = Client(info: try info())
        let task = controller.attach(client: client, network: "testnet")
        XCTAssertNotNil(controller.runtimeID) // Opening the runtime did not await the query.
        XCTAssertNil(controller.snapshot)
        let shared = controller.refresh()
        await client.waitForQuery()
        XCTAssertEqual(client.calls, 1)
        client.finish(.success(()))
        await task.value
        await shared.value
        XCTAssertEqual(controller.snapshot, client.info)
    }

    func testOfflineStartAndFailedRefreshPreserveVerifiedWarning() async throws {
        let controller = WalletProtocolCompatibilityController(foregroundNotification: foreground)
        let client = Client(info: try info())
        let start = controller.attach(client: client, network: "testnet")
        await client.waitForQuery()
        client.finish(.failure(TestError.offline))
        await start.value
        XCTAssertFalse(controller.snapshot!.newerProtocolAvailable)
        client.info = try info(true)
        let refresh = controller.refresh()
        await client.waitForQuery()
        client.finish(.failure(TestError.offline))
        await refresh.value
        XCTAssertTrue(controller.snapshot!.newerProtocolAvailable)
        client.snapshotError = TestError.offline
        let failedSnapshot = controller.refresh()
        await client.waitForQuery()
        client.finish(.failure(TestError.offline))
        await failedSnapshot.value
        XCTAssertTrue(controller.snapshot!.newerProtocolAvailable)
    }

    func testLateSuccessAndFailureCannotReplaceRecreatedRuntime() async throws {
        for staleFailure in [false, true] {
            let controller = WalletProtocolCompatibilityController(foregroundNotification: foreground)
            let old = Client(info: try info(true))
            let oldTask = controller.attach(client: old, network: "A")
            await old.waitForQuery()
            let middle = Client(info: try info())
            let middleTask = controller.attach(client: middle, network: "B")
            await middle.waitForQuery()
            let current = Client(info: try info())
            let currentTask = controller.attach(client: current, network: "A")
            await current.waitForQuery()
            current.finish(.success(()))
            await currentTask.value
            middle.finish(.success(()))
            old.finish(staleFailure ? .failure(TestError.offline) : .success(()))
            await middleTask.value
            await oldTask.value
            XCTAssertEqual(controller.snapshot, current.info)
            // A new runtime on the same network also gets a distinct identity.
            let previousID = controller.runtimeID
            let replacementTask = controller.attach(client: old, network: "A")
            XCTAssertNotEqual(controller.runtimeID, previousID)
            XCTAssertNil(controller.snapshot)
            await old.waitForQuery()
            controller.detach()
            old.finish(.success(()))
            await replacementTask.value
            XCTAssertNil(controller.snapshot)
        }
    }

    func testForegroundRefreshesButFaceIDActivationDoesNot() async throws {
        let center = NotificationCenter()
        let controller = WalletProtocolCompatibilityController(
            foregroundNotification: foreground, notificationCenter: center)
        let client = Client(info: try info())
        let start = controller.attach(client: client, network: "testnet")
        await client.waitForQuery()
        client.finish(.success(()))
        await start.value
        center.post(name: Notification.Name("test.didBecomeActive"), object: nil)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(client.calls, 1)
        center.post(name: foreground, object: nil)
        await client.waitForQuery()
        XCTAssertEqual(client.calls, 2)
        let shared = controller.refresh()
        client.finish(.success(()))
        await shared.value
    }

    func testBannerOnlyShowsVerifiedNewerObservationAndDistributionGuidance() async throws {
        let controller = WalletProtocolCompatibilityController(foregroundNotification: foreground)
        let model = ProtocolCompatibilityBannerViewModel(controller: controller)
        XCTAssertNil(model.message)
        let client = Client(info: try info())
        let start = controller.attach(client: client, network: "testnet")
        await client.waitForQuery()
        client.finish(.failure(TestError.offline))
        await start.value
        XCTAssertNil(model.message)
        client.info = try info(true)
        let refresh = controller.refresh()
        await client.waitForQuery()
        client.finish(.success(()))
        await refresh.value
        XCTAssertNotNil(model.message)
        #if Testflight
        XCTAssertTrue(model.message!.contains("TestFlight"))
        XCTAssertNil(model.updateURL)
        #else
        XCTAssertEqual(model.updateURL?.absoluteString, "https://apps.apple.com/app/dash-wallet/id1206647026")
        #endif
        controller.detach()
        XCTAssertNil(model.message)
    }

    private enum TestError: Error { case offline }

    private final class Client: WalletProtocolCompatibilityClient {
        var info: ProtocolVersionInfo
        var snapshotError: Error?
        private(set) var calls = 0
        private var continuation: CheckedContinuation<Void, Error>?
        init(info: ProtocolVersionInfo) { self.info = info }
        func queryEpoch() async throws {
            calls += 1
            try await withCheckedThrowingContinuation { continuation = $0 }
        }
        func protocolVersionInfo() throws -> ProtocolVersionInfo {
            if let snapshotError { throw snapshotError }
            return info
        }
        func waitForQuery() async {
            for _ in 0..<1000 {
                if continuation != nil { return }
                await Task.yield()
            }
            XCTFail("query did not start")
        }
        func finish(_ result: Result<Void, Error>) {
            let active = continuation
            continuation = nil
            active?.resume(with: result)
        }
    }
}
