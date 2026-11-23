//
//  CountedPhrasePluralTests.swift
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

import XCTest

/// Counted phrases pick their wording by the count and the language's plural
/// rules, and keep each count next to its own noun. The English cases read the
/// app's real catalog, so regenerating it cannot silently break an entry. The
/// Polish catalog has no translated plural forms yet, so Polish rule selection
/// runs on a fixture entry under the same key.
final class CountedPhrasePluralTests: XCTestCase {
    private let continueKey = "Continue with %1$d vote(s) across %2$d username(s)?"
    private let attemptsLeftKey = "%ld attempt(s) left before your wallet is disabled"
    private let attemptsRemainingKey = "%ld attempt(s) remaining"

    // MARK: English, real catalog

    func testContinueWithVotesAcrossUsernamesInEnglish() throws {
        let bundle = try appLocalization("en")

        XCTAssertEqual(format(continueKey, in: bundle, locale: "en", 1, 1),
                       "Continue with 1 vote across 1 username?")
        XCTAssertEqual(format(continueKey, in: bundle, locale: "en", 2, 1),
                       "Continue with 2 votes across 1 username?")
        XCTAssertEqual(format(continueKey, in: bundle, locale: "en", 1, 2),
                       "Continue with 1 vote across 2 usernames?")
        XCTAssertEqual(format(continueKey, in: bundle, locale: "en", 2, 2),
                       "Continue with 2 votes across 2 usernames?")
    }

    func testPinAttemptsInEnglish() throws {
        let bundle = try appLocalization("en")

        XCTAssertEqual(format(attemptsLeftKey, in: bundle, locale: "en", 1),
                       "1 attempt left before your wallet is disabled")
        XCTAssertEqual(format(attemptsLeftKey, in: bundle, locale: "en", 2),
                       "2 attempts left before your wallet is disabled")
        XCTAssertEqual(format(attemptsRemainingKey, in: bundle, locale: "en", 1),
                       "1 attempt remaining")
        XCTAssertEqual(format(attemptsRemainingKey, in: bundle, locale: "en", 2),
                       "2 attempts remaining")
    }

    func testCoinJoinWithdrawalCountsInEnglish() throws {
        let bundle = try appLocalization("en")

        XCTAssertEqual(format("%d transaction(s)", in: bundle, locale: "en", 1), "1 transaction")
        XCTAssertEqual(format("%d transaction(s)", in: bundle, locale: "en", 2), "2 transactions")
        XCTAssertEqual(format("%d UTXOs", in: bundle, locale: "en", 1), "1 UTXO")
        XCTAssertEqual(format("%d UTXOs", in: bundle, locale: "en", 22), "22 UTXOs")
    }

    func testVotingSummariesPickTheNounByTheTotalInEnglish() throws {
        let bundle = try appLocalization("en")

        XCTAssertEqual(format("%d of %d masternodes voted", in: bundle, locale: "en", 1, 2),
                       "1 of 2 masternodes voted")
        XCTAssertEqual(format("%d of %d masternodes voted", in: bundle, locale: "en", 2, 5),
                       "2 of 5 masternodes voted")
        XCTAssertEqual(format("%d of %d nodes voted", in: bundle, locale: "en", 1, 2),
                       "1 of 2 nodes voted")
        XCTAssertEqual(format("%d of %d nodes voted", in: bundle, locale: "en", 2, 5),
                       "2 of 5 nodes voted")
        XCTAssertEqual(format("%d of %d usernames voted on", in: bundle, locale: "en", 1, 2),
                       "1 of 2 usernames voted on")
        XCTAssertEqual(format("%d of %d usernames voted on", in: bundle, locale: "en", 2, 5),
                       "2 of 5 usernames voted on")
        XCTAssertEqual(format("%d of %d usernames voted on", in: bundle, locale: "en", 0, 1),
                       "0 of 1 username voted on")
    }

    /// Every English plural entry, formatted with 1 and with 2, fills all its
    /// markers and picks a form instead of showing "(s)".
    func testEveryEnglishPluralEntryFormatsCleanly() throws {
        let bundle = try appLocalization("en")
        let path = try XCTUnwrap(bundle.path(forResource: "Localizable", ofType: "stringsdict"))
        let entries = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: Any])
        XCTAssertFalse(entries.isEmpty)

        for key in entries.keys {
            for count in [1, 2] {
                let text = format(key, in: bundle, locale: "en", arguments: arguments(for: key, count: count))
                XCTAssertFalse(text.contains("%"), "\(key) with \(count): \(text)")
                XCTAssertFalse(text.contains("(s)"), "\(key) with \(count): \(text)")
            }
        }
    }

    // MARK: Polish rules, fixture entry

    func testPolishPluralRulesPickFewAndManyByCount() throws {
        let bundle = try polishFixture()

        XCTAssertEqual(format(continueKey, in: bundle, locale: "pl", 1, 1), "Oddać 1 głos na 1 nazwę?")
        XCTAssertEqual(format(continueKey, in: bundle, locale: "pl", 2, 1), "Oddać 2 głosy na 1 nazwę?")
        XCTAssertEqual(format(continueKey, in: bundle, locale: "pl", 5, 1), "Oddać 5 głosów na 1 nazwę?")
        XCTAssertEqual(format(continueKey, in: bundle, locale: "pl", 22, 1), "Oddać 22 głosy na 1 nazwę?")
        XCTAssertEqual(format(continueKey, in: bundle, locale: "pl", 2, 5), "Oddać 2 głosy na 5 nazw?")
    }

    // MARK: Polish, shipped catalog before translators deliver

    func testShippedPolishCatalogFillsEveryNumberMarker() throws {
        let bundle = try appLocalization("pl")

        let text = format(continueKey, in: bundle, locale: "pl", 2, 1)
        XCTAssertFalse(text.contains("%"), text)
        XCTAssertTrue(text.contains("2"), text)
        XCTAssertTrue(text.contains("1"), text)
    }

    // MARK: Helpers

    /// The same lookup and formatting the app does with `NSLocalizedString` and
    /// `String.localizedStringWithFormat`, with the language pinned.
    private func format(_ key: String, in bundle: Bundle, locale: String, _ args: CVarArg...) -> String {
        format(key, in: bundle, locale: locale, arguments: args)
    }

    private func format(_ key: String, in bundle: Bundle, locale: String, arguments args: [CVarArg]) -> String {
        let template = bundle.localizedString(forKey: key, value: nil, table: nil)
        return String(format: template, locale: Locale(identifier: locale), arguments: args)
    }

    /// One argument per marker of the key, in argument order: `count` for
    /// numbers, a word for `%@`.
    private func arguments(for key: String, count: Int) -> [CVarArg] {
        let regex = try! NSRegularExpression(pattern: "%(?:(\\d+)\\$)?(l?[du]|@)")
        let matches = regex.matches(in: key, range: NSRange(key.startIndex..., in: key))
        let markers = matches.enumerated().map { offset, match -> (position: Int, type: String) in
            let position = Range(match.range(at: 1), in: key).flatMap { Int(key[$0]) } ?? offset + 1
            return (position, String(key[Range(match.range(at: 2), in: key)!]))
        }
        let args = markers.sorted { $0.position < $1.position }.map { marker -> CVarArg in
            switch marker.type {
            case "@": return "word"
            case "u", "lu": return UInt(count)
            default: return count
            }
        }
        // ShieldedSyncInfoScreen shows the count already formatted and passes the
        // number after it only to pick the form.
        return key == "%@ notes" ? ["\(count)", UInt64(count)] : args
    }

    private func appLocalization(_ language: String) throws -> Bundle {
        let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"),
                                 "the app bundle has no \(language).lproj")
        return try XCTUnwrap(Bundle(path: path))
    }

    private func polishFixture() throws -> Bundle {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CountedPhrasePluralTests-\(UUID().uuidString).bundle")
        let lproj = root.appendingPathComponent("pl.lproj")
        try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        func rule(_ forms: [String: String]) -> [String: String] {
            forms.merging([
                "NSStringFormatSpecTypeKey": "NSStringPluralRuleType",
                "NSStringFormatValueTypeKey": "d",
            ]) { current, _ in current }
        }
        let entry: [String: Any] = [
            "NSStringLocalizedFormatKey": "Oddać %1$#@votes@ na %2$#@names@?",
            "votes": rule(["one": "%1$d głos", "few": "%1$d głosy", "many": "%1$d głosów", "other": "%1$d głosu"]),
            "names": rule(["one": "%2$d nazwę", "few": "%2$d nazwy", "many": "%2$d nazw", "other": "%2$d nazwy"]),
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: [continueKey: entry], format: .xml, options: 0)
        try data.write(to: lproj.appendingPathComponent("Localizable.stringsdict"))
        return try XCTUnwrap(Bundle(url: root))
    }
}
