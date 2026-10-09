//
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

import XCTest
@testable import dashpay

@MainActor
final class ContestedUsernameFeeTests: XCTestCase {
    private typealias Amounts = ContestedUsernameFee.Amounts

    private struct ReadFailed: Error {}

    private final class ReadCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int { lock.withLock { value } }
        func increment() { lock.withLock { value += 1 } }
    }

    /// The network a test resolver believes is running, and what a read of
    /// its protocol version returns (nil = the read fails).
    private final class Network {
        var scope: String? = "testnet"
        var version: UInt32?
    }

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ContestedUsernameFeeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeFee(_ network: Network) -> ContestedUsernameFee {
        ContestedUsernameFee(defaults: defaults, source: {
            guard let scope = network.scope else { return nil }
            let version = network.version
            return (scope, {
                guard let version else { throw ReadFailed() }
                return version
            })
        })
    }

    func testAmountsByProtocolVersion() {
        XCTAssertEqual(Amounts.forProtocolVersion(nil), .legacy)
        XCTAssertEqual(Amounts.forProtocolVersion(13), .legacy)
        XCTAssertEqual(Amounts.forProtocolVersion(14), .reduced)
        XCTAssertEqual(Amounts.forProtocolVersion(15), .reduced)

        XCTAssertEqual(Amounts.legacy.fundCredits, 20_000_000_000)
        XCTAssertEqual(Amounts.legacy.fundDuffs, 20_000_000)
        XCTAssertEqual(Amounts.legacy.fundingDuffs, 25_000_000)
        XCTAssertEqual(Amounts.reduced.fundCredits, 10_000_000_000)
        XCTAssertEqual(Amounts.reduced.fundDuffs, 10_000_000)
        XCTAssertEqual(Amounts.reduced.fundingDuffs, 15_000_000)
    }

    /// An existing identity needs the fund plus the per-name fee headroom,
    /// and what a new identity is funded with covers that for two names.
    func testRegistrationCreditsFollowTheFund() {
        typealias Coordinator = DWIdentityRegistrationCoordinator
        for amounts in [Amounts.legacy, Amounts.reduced] {
            let oneName = Coordinator.requiredRegistrationCredits(
                isContested: true, nameCount: 1, contestFundCredits: amounts.fundCredits)
            let twoNames = Coordinator.requiredRegistrationCredits(
                isContested: true, nameCount: 2, contestFundCredits: amounts.fundCredits)
            XCTAssertEqual(oneName, amounts.fundCredits + Coordinator.registrationFeeHeadroomCreditsPerName)
            XCTAssertLessThan(twoNames, amounts.fundingDuffs * 1_000)
        }
        XCTAssertEqual(
            Coordinator.requiredRegistrationCredits(
                isContested: false, nameCount: 1, contestFundCredits: Amounts.reduced.fundCredits),
            Coordinator.registrationFeeHeadroomCreditsPerName)
    }

    /// What a new identity is funded with: the Dash and Platform balances
    /// follow the protocol version, Shielded's exit denomination does not.
    func testNewIdentityFundingBySource() {
        for amounts in [Amounts.legacy, Amounts.reduced] {
            XCTAssertEqual(amounts.newIdentityFundingDuffs(isContested: false, fromShielded: false), 3_000_000)
            XCTAssertEqual(amounts.newIdentityFundingDuffs(isContested: false, fromShielded: true), 10_000_000)
            XCTAssertEqual(amounts.newIdentityFundingDuffs(isContested: true, fromShielded: true), 25_000_000)
        }
        XCTAssertEqual(Amounts.legacy.newIdentityFundingDuffs(isContested: true, fromShielded: false), 25_000_000)
        XCTAssertEqual(Amounts.reduced.newIdentityFundingDuffs(isContested: true, fromShielded: false), 15_000_000)
        // "Some usernames cost up to": Shielded keeps it at 0.25 on protocol 14.
        XCTAssertEqual(Amounts.legacy.maximumUsernameCostDuffs, 25_000_000)
        XCTAssertEqual(Amounts.reduced.maximumUsernameCostDuffs, 25_000_000)
    }

    /// The form states the figure of the source it holds, and judges the
    /// Dash balance at its own figure whichever source that is.
    func testFormFigureFollowsItsSource() {
        let model = CreateUsernameViewModel.makeForPreview()
        XCTAssertEqual(model.newIdentityFundingDuffs(isContested: false), 3_000_000)
        model.setActiveFundingSource(.shielded)
        XCTAssertEqual(model.newIdentityFundingDuffs(isContested: false), 10_000_000)
        XCTAssertEqual(model.newIdentityFundingDuffs(isContested: true), 25_000_000)
        XCTAssertEqual(model.newIdentityFundingDuffs(isContested: false, source: .core), 3_000_000)
        model.setActiveFundingSource(.core)
        XCTAssertEqual(model.newIdentityFundingDuffs(isContested: false), 3_000_000)
        XCTAssertEqual(model.newIdentityFundingDuffs(isContested: true, source: .shielded), 25_000_000)
    }

    func testUnknownVersionChargesTheLegacyAmounts() async {
        let network = Network()
        let fee = makeFee(network)
        XCTAssertEqual(fee.amounts, .legacy)

        // A read that throws leaves it there.
        await fee.refresh()
        XCTAssertEqual(fee.amounts, .legacy)

        // So does no running network at all.
        network.scope = nil
        network.version = 14
        await fee.refresh()
        XCTAssertEqual(fee.amounts, .legacy)
    }

    func testFollowsTheNetworkAcrossActivation() async {
        let network = Network()
        network.version = 13
        let fee = makeFee(network)
        await fee.refresh()
        XCTAssertEqual(fee.amounts, .legacy)

        network.version = 14
        await fee.refresh()
        XCTAssertEqual(fee.amounts, .reduced)
    }

    /// A figure shown to the user must not grow before it is paid: neither a
    /// failed read nor a lower one takes back a version already learned.
    func testLearnedVersionIsNeverLowered() async {
        let network = Network()
        network.version = 14
        let fee = makeFee(network)
        await fee.refresh()
        XCTAssertEqual(fee.amounts, .reduced)

        network.version = nil
        await fee.refresh()
        XCTAssertEqual(fee.amounts, .reduced)

        network.version = 13
        await fee.refresh()
        XCTAssertEqual(fee.amounts, .reduced)
    }

    func testLearnedVersionSurvivesARelaunch() async {
        let network = Network()
        network.version = 14
        await makeFee(network).refresh()

        // A new process: nothing read yet, and the first read fails.
        network.version = nil
        let relaunched = makeFee(network)
        XCTAssertEqual(relaunched.amounts, .reduced)
        await relaunched.refresh()
        XCTAssertEqual(relaunched.amounts, .reduced)
    }

    func testEachNetworkKeepsItsOwnVersion() async {
        let network = Network()
        network.version = 14
        let fee = makeFee(network)
        await fee.refresh()
        XCTAssertEqual(fee.amounts, .reduced)

        // Mainnet has not upgraded; its read fails, so nothing is known.
        network.scope = "mainnet"
        network.version = nil
        await fee.refresh()
        XCTAssertEqual(fee.amounts, .legacy)

        network.scope = "testnet"
        await fee.refresh()
        XCTAssertEqual(fee.amounts, .reduced)
    }

    /// A runtime that starts on a network publishes that network's figure at
    /// once, not the previous network's.
    func testRuntimeStartPublishesItsOwnNetwork() async {
        let network = Network()
        network.version = 14
        let fee = makeFee(network)
        await fee.refresh()
        XCTAssertEqual(fee.amounts, .reduced)

        fee.runtimeDidStop()
        network.scope = "mainnet"
        network.version = 13
        fee.runtimeDidStart()
        XCTAssertEqual(fee.amounts, .legacy)
        await fee.refresh()
        XCTAssertEqual(fee.amounts, .legacy)

        fee.runtimeDidStop()
        network.scope = "testnet"
        fee.runtimeDidStart()
        XCTAssertEqual(fee.amounts, .reduced)
        await fee.refresh()
    }

    /// Once the reduced pair is known no read can change it, so none is made.
    func testNoReadOnceTheReducedPairIsKnown() async {
        let reads = ReadCounter()
        let fee = ContestedUsernameFee(defaults: defaults, source: {
            ("testnet", {
                reads.increment()
                return 14
            })
        })
        await fee.refresh()
        await fee.refresh()
        XCTAssertEqual(fee.amounts, .reduced)
        XCTAssertEqual(reads.count, 1)
    }

    /// Below the reduced pair every call reads again, so a read that did not
    /// reach the network is made good the next time a screen opens.
    func testReadsAgainWhileTheLegacyPairStands() async {
        let reads = ReadCounter()
        let fee = ContestedUsernameFee(defaults: defaults, source: {
            ("mainnet", {
                reads.increment()
                return 13
            })
        })
        await fee.refresh()
        await fee.refresh()
        XCTAssertEqual(fee.amounts, .legacy)
        XCTAssertEqual(reads.count, 2)
    }

    func testPublishesWhenTheVersionArrives() async {
        let network = Network()
        network.version = 14
        let fee = makeFee(network)
        var published: [Amounts] = []
        let subscription = fee.$amounts.sink { published.append($0) }
        await fee.refresh()
        subscription.cancel()
        XCTAssertEqual(published, [.legacy, .reduced])
    }
}
