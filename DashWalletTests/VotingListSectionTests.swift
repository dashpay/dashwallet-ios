//
//  VotingListSectionTests.swift
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

/// The voting list's day groups and the toast text.
final class VotingListSectionTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        return calendar
    }()

    /// 2026-11-02 10:00 in Kyiv.
    private lazy var now: Date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 10))!

    private func contest(_ label: String, endsIn hours: Double?) -> DPNSContest {
        DPNSContest(
            normalizedLabel: label,
            endTime: hours.map { now.addingTimeInterval($0 * 3600) },
            hasWinner: false,
            abstainVotes: 0,
            lockVotes: 0,
            contenders: [])
    }

    func testGroupsByCalendarDayNotByHours() {
        let sections = VotingListSection.group([
            contest("late-today", endsIn: 13.9),   // 23:54 today
            contest("early-tomorrow", endsIn: 14.1), // 00:06 tomorrow
            contest("three-days", endsIn: 72),
        ], now: now, calendar: calendar)

        XCTAssertEqual(sections.map(\.daysLeft), [0, 1, 3])
        XCTAssertEqual(sections[0].contests.map(\.normalizedLabel), ["late-today"])
        XCTAssertEqual(sections[1].contests.map(\.normalizedLabel), ["early-tomorrow"])
    }

    /// A contest whose end has already passed is closing, so it reads as
    /// "today", never as a negative number of days.
    func testPastEndCountsAsToday() {
        let sections = VotingListSection.group([contest("closing", endsIn: -30)], now: now, calendar: calendar)
        XCTAssertEqual(sections.map(\.daysLeft), [0])
    }

    func testUnknownEndGoesLast() {
        let sections = VotingListSection.group([
            contest("unknown", endsIn: nil),
            contest("soon", endsIn: 1),
        ], now: now, calendar: calendar)
        XCTAssertEqual(sections.map(\.daysLeft), [0, nil])
    }

    /// Sections go soonest first; rows inside one keep the list's sort order.
    func testRowsKeepTheirOrderInsideASection() {
        let sections = VotingListSection.group([
            contest("b", endsIn: 50),
            contest("z", endsIn: 2),
            contest("a", endsIn: 49),
        ], now: now, calendar: calendar)
        XCTAssertEqual(sections.map(\.daysLeft), [0, 2])
        XCTAssertEqual(sections[1].contests.map(\.normalizedLabel), ["b", "a"])
    }

    func testEmptyListHasNoSections() {
        XCTAssertTrue(VotingListSection.group([], now: now, calendar: calendar).isEmpty)
    }

    /// A cast applied locally right after it was recorded matches what the
    /// store would read back: the node holds the new choice and has spent one
    /// more of its casts.
    func testRecordedCastUpdatesTheLiveVoteAndTheCastCount() {
        let node = Data([1, 2, 3])
        var history = VotingViewModel.NodeVoteHistory([
            CastVoteRecord(proTxHash: node, normalizedLabel: "pizza", choice: .lock,
                           castAt: now, castCount: 4),
        ])
        XCTAssertTrue(history.hasCastsLeft(node))

        history.recordCast(of: node, on: "pizza", choice: .abstain, at: now.addingTimeInterval(60))

        XCTAssertEqual(history.liveChoice(of: node), .abstain)
        XCTAssertEqual(history.liveChoices(of: [node]), [.abstain])
        XCTAssertFalse(history.hasCastsLeft(node), "the fifth cast spends the last one")
    }

    func testVotedToastNamesTheUsername() {
        let toast = VotingToast.voted(username: "johndoe")
        XCTAssertTrue(toast.message.contains("johndoe"))
    }

    /// AC-21: a pill's spoken vote count follows the plural rules: «1 vote», «3 votes».
    func testVoteCountIsSpokenWithPluralRules() {
        XCTAssertEqual(VotingContestCard.votesValue(count: 1), "1 vote")
        XCTAssertEqual(VotingContestCard.votesValue(count: 3), "3 votes")
        XCTAssertEqual(VotingContestCard.votesValue(count: 0), "0 votes")
    }

    /// AC-01: the header count and the day headings follow English plural
    /// rules: «1 username», «Voting ends in 1 day».
    func testHeaderCountAndDayHeadingsUseEnglishPlurals() {
        let usernames = { (count: Int) in
            String.localizedStringWithFormat(NSLocalizedString("%d usernames", comment: "Voting"), count)
        }
        XCTAssertEqual(usernames(1), "1 username")
        XCTAssertEqual(usernames(2), "2 usernames")

        let sections = VotingListSection.group([
            contest("tomorrow", endsIn: 24),
            contest("three-days", endsIn: 72),
        ], now: now, calendar: calendar)
        XCTAssertEqual(sections.map(\.title), ["Voting ends in 1 day", "Voting ends in 3 days"])
    }

    /// Every app locale carries a plural entry for each counted voting phrase,
    /// so no language falls back to an invariant «%d …» text.
    func testCountedVotingPhrasesHaveAPluralEntryInEveryLocale() throws {
        let keys = ["%d votes", "All %d nodes", "%d usernames", "Voting ends in %d days"]
        let root = URL(fileURLWithPath: Bundle.main.bundlePath)
        let paths = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(".lproj") }
            .map { root.appendingPathComponent($0).appendingPathComponent("Localizable.stringsdict").path }
            .filter { FileManager.default.fileExists(atPath: $0) }
        XCTAssertFalse(paths.isEmpty)
        for path in paths {
            let dict = try XCTUnwrap(NSDictionary(contentsOfFile: path))
            for key in keys {
                XCTAssertNotNil(dict[key], "\(key) missing in \(path)")
            }
        }
    }
}
