//
//  VotingFilterTests.swift
//  DashWalletTests
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

@testable import dashpay
import SwiftDashSDK
import XCTest

/// The voting list's filter: type, duplicates and order.
final class VotingFilterTests: XCTestCase {

    private func contest(
        _ label: String, requests: Int = 1, votes: UInt32 = 0, lockVotes: UInt32 = 0, endsInHours: Double? = nil
    ) -> DPNSContest {
        DPNSContest(
            normalizedLabel: label,
            endTime: endsInHours.map { Date(timeIntervalSince1970: 1_800_000_000 + $0 * 3600) },
            hasWinner: false,
            abstainVotes: 0,
            lockVotes: lockVotes,
            contenders: (0..<requests).map { index in
                DPNSContender(identityId: "\(label)-\(index)", voteTally: index == 0 ? votes : 0)
            })
    }

    /// Oldest request (soonest end) first.
    private lazy var contests = [
        contest("approved", votes: 3, endsInHours: 1),
        contest("blocked", lockVotes: 2, endsInHours: 2),
        contest("abstained", requests: 2, votes: 5, endsInHours: 3),
        contest("untouched", requests: 3, votes: 3, endsInHours: 4),
    ]

    private let choices: [String: Set<VoteChoice>] = [
        "approved": [.towards(identityId: "approved-0")],
        "blocked": [.lock],
        "abstained": [.abstain],
    ]

    private func labels(_ filter: VotingFilter) -> [String] {
        filter.apply(to: contests) { self.choices[$0] ?? [] }.map(\.normalizedLabel)
    }

    func testDefaultShowsEverythingOldestFirst() {
        XCTAssertEqual(labels(.default), ["approved", "blocked", "abstained", "untouched"])
        XCTAssertEqual(VotingFilter.default, VotingFilter(sort: .dateOldToNew, type: .all, onlyDuplicates: false))
    }

    /// The date orders follow the end, whatever order the contests arrive in;
    /// an unknown end goes last both ways.
    func testDateOrdersFollowTheEndAndPutAnUnknownEndLast() {
        let shuffled = [
            contest("unknown"),
            contest("late", endsInHours: 5),
            contest("early", endsInHours: 1),
            contest("middle", endsInHours: 3),
        ]
        var filter = VotingFilter.default
        XCTAssertEqual(filter.apply(to: shuffled) { _ in [] }.map(\.normalizedLabel), ["early", "middle", "late", "unknown"])
        filter.sort = .dateNewToOld
        XCTAssertEqual(filter.apply(to: shuffled) { _ in [] }.map(\.normalizedLabel), ["late", "middle", "early", "unknown"])
    }

    func testIHaveApprovedKeepsNamesThisWalletVotedTowards() {
        var filter = VotingFilter.default
        filter.type = .approved
        XCTAssertEqual(labels(filter), ["approved"])
    }

    /// Any recorded vote counts, block and abstain included.
    func testIHaveNotVotedKeepsOnlyNamesWithoutAVote() {
        var filter = VotingFilter.default
        filter.type = .notVoted
        XCTAssertEqual(labels(filter), ["untouched"])
    }

    func testHasBlockedVotesReadsTheTallyNotThisWalletsVote() {
        var filter = VotingFilter.default
        filter.type = .hasBlockedVotes
        XCTAssertEqual(labels(filter), ["blocked"])
    }

    func testOnlyDuplicatesKeepsNamesWithSeveralRequests() {
        var filter = VotingFilter.default
        filter.onlyDuplicates = true
        XCTAssertEqual(labels(filter), ["abstained", "untouched"])

        filter.type = .notVoted
        XCTAssertEqual(labels(filter), ["untouched"])
    }

    /// Days stay soonest first whatever the sort; the sort orders names inside a day.
    func testSortOrdersNamesInsideEachDay() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let today = calendar.startOfDay(for: now)
        func ending(_ label: String, day: Int, hour: Int, votes: UInt32) -> DPNSContest {
            DPNSContest(
                normalizedLabel: label,
                endTime: calendar.date(byAdding: .hour, value: day * 24 + hour, to: today),
                hasWinner: false,
                abstainVotes: 0,
                lockVotes: 0,
                contenders: [DPNSContender(identityId: label, voteTally: votes)])
        }
        let list = [
            ending("a", day: 1, hour: 2, votes: 1),
            ending("b", day: 1, hour: 20, votes: 9),
            ending("c", day: 3, hour: 1, votes: 5),
            ending("d", day: 3, hour: 22, votes: 0),
        ]
        func grouped(_ sort: ContestSort) -> [[String]] {
            var filter = VotingFilter.default
            filter.sort = sort
            return VotingListSection.group(filter.apply(to: list) { _ in [] }, now: now, calendar: calendar)
                .map { $0.contests.map(\.normalizedLabel) }
        }
        XCTAssertEqual(grouped(.dateOldToNew), [["a", "b"], ["c", "d"]])
        XCTAssertEqual(grouped(.dateNewToOld), [["b", "a"], ["d", "c"]])
        XCTAssertEqual(grouped(.votesHighToLow), [["b", "a"], ["c", "d"]])
        XCTAssertEqual(grouped(.votesLowToHigh), [["a", "b"], ["d", "c"]])
    }

    /// Equal totals keep the order they came in, both ways.
    func testVoteOrdersAreStable() {
        var filter = VotingFilter.default
        filter.sort = .votesHighToLow
        XCTAssertEqual(labels(filter), ["abstained", "approved", "untouched", "blocked"])

        filter.sort = .votesLowToHigh
        XCTAssertEqual(labels(filter), ["blocked", "approved", "untouched", "abstained"])
    }

    /// A name whose history is not known is neither "approved" nor "not voted".
    func testUnknownHistoryIsLeftOutOfTheTypesByMyVote() {
        let known: (String) -> Set<VoteChoice>? = { $0 == "approved" ? self.choices[$0] : nil }
        var filter = VotingFilter.default
        filter.type = .notVoted
        XCTAssertEqual(filter.apply(to: contests, myChoices: known).map(\.normalizedLabel), [])
        filter.type = .approved
        XCTAssertEqual(filter.apply(to: contests, myChoices: known).map(\.normalizedLabel), ["approved"])
        filter.type = .hasBlockedVotes
        XCTAssertEqual(filter.apply(to: contests, myChoices: known).map(\.normalizedLabel), ["blocked"])
    }

    func testTitleNamesTheTypeAndTheDuplicatesSwitch() {
        var filter = VotingFilter.default
        XCTAssertEqual(filter.title, VotingTypeFilter.all.title)
        filter.onlyDuplicates = true
        filter.type = .notVoted
        XCTAssertTrue(filter.title.hasPrefix(VotingTypeFilter.notVoted.title))
        XCTAssertNotEqual(filter.title, VotingTypeFilter.notVoted.title)
    }

    func testSortRawValuesAreStable() {
        XCTAssertEqual(ContestSort.allCases.map(\.rawValue), ["dateNewToOld", "dateOldToNew", "votesHighToLow", "votesLowToHigh"])
        XCTAssertEqual(VotingTypeFilter.allCases.map(\.rawValue), ["all", "approved", "notVoted", "hasBlockedVotes"])
    }
}
