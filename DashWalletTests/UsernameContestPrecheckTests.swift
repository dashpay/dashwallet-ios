//
//  UsernameContestPrecheckTests.swift
//  DashWalletTests
//

import SwiftDashSDK
import XCTest
@testable import dashpay

/// `UsernameMarketplaceService.contestPrecheck(voteState:)` against the
/// payload shapes `dash_sdk_dpns_get_contested_vote_state` answers with.
final class UsernameContestPrecheckTests: XCTestCase {
    private typealias Precheck = UsernameMarketplaceService.ContestPrecheck

    private let winnerId = "4EfA9Jrvv3nnCFdSf7fad59851iiTRZ6Wcu6YVJ4iSeF"

    /// Parses `json` the way the SDK does, so the mapping meets the same
    /// Foundation values (`NSString`, `NSNull`, `NSArray`) it does in the app.
    private func precheck(_ json: String) throws -> Precheck {
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        let state = try XCTUnwrap(object as? [String: Any])
        return UsernameMarketplaceService.contestPrecheck(voteState: .success(state))
    }

    private func contenders(_ count: Int) -> String {
        let entries = (0..<count).map { #"{"identifier":"contender\#($0)","votes":"ContenderVotes(\#($0))"}"# }
        return "[" + entries.joined(separator: ",") + "]"
    }

    func testALabelWithNoContendersStartsAFreshVote() throws {
        XCTAssertEqual(try precheck(#"{"contenders":[]}"#), .fresh)
        XCTAssertEqual(try precheck(#"{"winner":null,"contenders":[],"abstainVotes":0,"lockVotes":0}"#), .fresh)
    }

    func testALabelAVoteLockedIsLocked() throws {
        XCTAssertEqual(try precheck(#"{"winner":"LOCKED","contenders":[]}"#), .locked)
        XCTAssertEqual(try precheck(#"{"winner":"LOCKED","contenders":\#(contenders(2))}"#), .locked)
    }

    func testALabelAnIdentityWonIsLocked() throws {
        XCTAssertEqual(try precheck(#"{"winner":"\#(winnerId)","contenders":[]}"#), .locked)
        XCTAssertEqual(try precheck(#"{"winner":"\#(winnerId)","contenders":\#(contenders(3))}"#), .locked)
    }

    func testContendersWithNoWinnerAreAnActiveContestWithTheirCount() throws {
        XCTAssertEqual(try precheck(#"{"contenders":\#(contenders(1))}"#),
                       .activeContest(contenders: 1, endsAt: nil))
        XCTAssertEqual(try precheck(#"{"contenders":\#(contenders(3)),"abstainVotes":2,"lockVotes":1}"#),
                       .activeContest(contenders: 3, endsAt: nil))
        XCTAssertEqual(try precheck(#"{"winner":null,"contenders":\#(contenders(2))}"#),
                       .activeContest(contenders: 2, endsAt: nil))
    }

    /// A failure says nothing about the label, whatever its text reads:
    /// "not found" used to be taken for "no contest".
    func testAFailedQueryLeavesTheStateUnknown() {
        let failures: [Error] = [
            SDKError.internalError("DPNS contract not found"),
            SDKError.notFound("No data returned"),
            SDKError.internalError("no contest for this name"),
            SDKError.serializationError("Failed to parse vote state JSON"),
            URLError(.timedOut),
            CancellationError()
        ]
        for failure in failures {
            XCTAssertEqual(UsernameMarketplaceService.contestPrecheck(voteState: .failure(failure)), .unknown,
                           "\(failure)")
        }
    }
}
