//
//  Created by Roman Chornyi
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Combine
import XCTest

#if canImport(dashpay)
@testable import dashpay
#elseif canImport(dashwallet)
@testable import dashwallet
#else
#error("Unknown test host module")
#endif

/// A data source whose metadata lookup waits until the test lets it go.
private final class DelayedLookupDataSource: DashConnectDataSource {
    var connections: AnyPublisher<[DAppConnection], Never> { Just([]).eraseToAnyPublisher() }

    /// Resumed by `finishLookup()`.
    private var lookup: CheckedContinuation<Void, Never>?
    private(set) var lookups = 0

    func finishLookup() {
        let waiting = lookup
        lookup = nil
        waiting?.resume()
    }

    func parseQR(_ content: String) async throws -> DashConnectQr {
        .login(MockDashConnectDataSource.sampleLoginRequest)
    }

    func makeConnectionRequest(from loginRequest: DashKeyRequest) async -> ConnectionRequest {
        lookups += 1
        await withCheckedContinuation { lookup = $0 }
        return ConnectionRequest(loginRequest: loginRequest)
    }

    func approveLogin(_ request: DashKeyRequest) async throws -> DAppConnection {
        throw DashConnectMockError.approveFailed
    }

    func handleStateTransition(_ request: DashStRequest) async throws -> DashConnectStAction {
        throw DashConnectMockError.stateTransitionNotSupported
    }

    func approveTokenPurchase(_ request: DashConnectTokenPurchaseRequest) async throws {
        throw DashConnectMockError.approveFailed
    }

    func disconnect(id: String) async {}
    func remove(id: String) async {}
}

/// The deep-link queue hands a `dash-key:` link to the Connections screen and
/// waits for the view model's settlement — the approval sheet published, or
/// a refusal shown — before the next link. Without it, a second link that
/// arrived during the metadata lookup superseded the first and discarded
/// its approval.
@MainActor
final class ConnectionsViewModelTests: XCTestCase {
    private func settle(_ condition: @autoclosure @escaping () -> Bool, within seconds: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    func testTwoQueuedLinksWithADelayedLookupSettleInTurnAndKeepTheFirstApproval() async {
        let dataSource = DelayedLookupDataSource()
        let viewModel = ConnectionsViewModel(dataSource: dataSource, featureUnavailable: false)
        let link = MockDashConnectDataSource.sampleLoginQRCode

        var firstSettled = 0
        viewModel.onURIReceived(link) { firstSettled += 1 }
        await settle(dataSource.lookups == 1)
        XCTAssertEqual(firstSettled, 0, "the lookup is still running: the queue stays busy")
        XCTAssertNil(viewModel.pendingRequest)

        dataSource.finishLookup()
        await settle(firstSettled == 1)
        XCTAssertEqual(firstSettled, 1, "settled once the approval sheet was published")
        XCTAssertEqual(viewModel.pendingRequest, MockDashConnectDataSource.sampleRequest)

        // The queue hands the second link over only now; the first request is
        // on screen and owns it, so the second is refused — and settles at once.
        var secondSettled = 0
        viewModel.onURIReceived(link) { secondSettled += 1 }
        XCTAssertEqual(secondSettled, 1, "a refusal settles immediately")
        XCTAssertEqual(viewModel.pendingRequest, MockDashConnectDataSource.sampleRequest, "the first approval is still the one on screen")
        XCTAssertNotNil(viewModel.approveError, "the refusal is shown on the sheet")
        XCTAssertEqual(dataSource.lookups, 1, "no second lookup")
    }

    func testASupersededRequestSettlesSoTheQueueIsNotHeldByIt() async {
        let dataSource = DelayedLookupDataSource()
        let viewModel = ConnectionsViewModel(dataSource: dataSource, featureUnavailable: false)
        let link = MockDashConnectDataSource.sampleLoginQRCode

        var firstSettled = 0
        viewModel.onURIReceived(link) { firstSettled += 1 }
        await settle(dataSource.lookups == 1)

        // A QR scan from the screen itself (not the queue) supersedes the
        // resolving request: the queue's link settles right there.
        viewModel.onQRScanned(link)
        XCTAssertEqual(firstSettled, 1)

        dataSource.finishLookup()
        await settle(dataSource.lookups == 2)
        dataSource.finishLookup()
        await settle(viewModel.pendingRequest != nil)
        XCTAssertEqual(firstSettled, 1, "settled once, not again when the superseded lookup returns")
    }

    func testAnUnavailableFeatureSettlesAtOnce() {
        let viewModel = ConnectionsViewModel(dataSource: DelayedLookupDataSource(), featureUnavailable: true)
        var settled = 0
        viewModel.onURIReceived(MockDashConnectDataSource.sampleLoginQRCode) { settled += 1 }
        XCTAssertEqual(settled, 1)
    }
}
