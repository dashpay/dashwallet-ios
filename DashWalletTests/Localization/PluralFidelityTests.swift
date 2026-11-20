//
//  PluralFidelityTests.swift
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

/// Every counted phrase of the Baseline, formatted from the app's compiled String Catalog in each
/// locale the app ships, for the counts 0, 1, 2, 5, 21 and 101, gives the Baseline form; and no
/// counted phrase of the Baseline has plural variants in a locale whose Baseline lacked them.
/// Counted phrases added since the Baseline are not held to it.
///
/// A phrase the code looks up with an interpolation (`String(localized: "\(count) words")`) is
/// formatted through that same call; any other phrase with `String(format:locale:arguments:)` over
/// the table text. Both get the locale under test, so its plural rules apply whatever the
/// simulator's language is.
///
/// `BaselinePluralForms.json` is written from the Baseline lists by the zero-loss check's formatter:
///
///     python3 scripts/localization/baseline_plural_forms.py
///
/// Rerun it after every rebase, once the zero-loss check rewrote its key map. The Catalog's other
/// 21 locales are not compiled into the app; the zero-loss check formats them with the same counts.
final class PluralFidelityTests: XCTestCase {
    private struct Fixture: Decodable {
        let baseline: String
        let counts: [Int]
        let locales: [String]
        let phrases: [Phrase]
        let variant_keys: [String: [String]]
    }

    private struct Phrase: Decodable {
        let baseline_key: String
        let key: String
        let interpolated: Bool
        let types: [String]
        let args: [[Argument]]
        let forms: [String: [String]?]
    }

    private enum Argument: Decodable {
        case number(Double)
        case text(String)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Double.self) {
                self = .number(value)
            } else {
                self = .text(try container.decode(String.self))
            }
        }
    }

    func testEveryCountedPhraseGivesTheBaselineFormInEveryShippedLocale() throws {
        let fixture = try loadFixture()
        var checked = 0
        var mismatches: [String] = []

        for locale in fixture.locales {
            let bundle = try localization(locale)
            for phrase in fixture.phrases {
                // nil: the Baseline translation takes an argument as the wrong type (a defect the
                // zero-loss check reports too); the Catalog fixes it on purpose.
                guard let expected = phrase.forms[locale].flatMap({ $0 }) else { continue }
                for (index, count) in fixture.counts.enumerated() {
                    let actual = try format(phrase, arguments: phrase.args[index], in: bundle, locale: locale)
                    checked += 1
                    if actual != expected[index] {
                        mismatches.append("\(phrase.key) [Baseline \(phrase.baseline_key)] locale=\(locale) "
                            + "count=\(count) expected=\(expected[index]) actual=\(actual)")
                    }
                }
            }
        }

        XCTAssertGreaterThan(checked, 0)
        XCTAssertTrue(mismatches.isEmpty,
                      "\(mismatches.count) of \(checked) forms differ from the Baseline:\n"
                          + mismatches.prefix(40).joined(separator: "\n"))
    }

    func testNoLocaleHasPluralVariantsItsBaselineLacked() throws {
        let fixture = try loadFixture()
        for locale in fixture.locales {
            let bundle = try localization(locale)
            let path = try XCTUnwrap(bundle.path(forResource: "Localizable", ofType: "stringsdict"),
                                     "\(locale).lproj has no compiled plural table")
            let entries = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: Any])
            for key in Self.variantsTheBaselineLacked(Array(entries.keys), in: locale, fixture.variant_keys) {
                XCTFail("\(key) has plural variants in \(locale), which its Baseline did not have")
            }
        }
    }

    func testOnlyTheBaselinesCountedPhrasesAreHeldToItsVariants() {
        let baseline = ["en": ["%d syncs", "%d items"], "uk": ["%d items"]]
        XCTAssertEqual(Self.variantsTheBaselineLacked(["%d items", "%d syncs"], in: "uk", baseline), ["%d syncs"])
        XCTAssertEqual(Self.variantsTheBaselineLacked(["%d items", "%lld new phrases"], in: "uk", baseline), [])
    }

    /// The two Baseline defects: `ja` and `tr` took `%d merchant(s) in %@` with unnumbered codes in
    /// swapped order, so the Baseline formatted undefined text. The Catalog numbers the codes, so the
    /// count and the place both show: the one intended wording change of the move.
    func testTheFixedJapaneseAndTurkishMerchantCountShowTheCountAndThePlace() throws {
        let key = "%d merchant(s) in %@"
        // locale → [count: expected text]
        let cases: [String: [Int: String]] = [
            "ja": [5: "2 km で 5 の加盟店"],
            "tr": [1: "2 km içinde 1 tüccarlar", 5: "2 km içinde 5 satıcılar"],
        ]
        for (locale, expected) in cases {
            let bundle = try localization(locale)
            let template = bundle.localizedString(forKey: key, value: nil, table: "Localizable")
            for (count, text) in expected {
                let actual = String(format: template, locale: Locale(identifier: locale), arguments: [count, "2 km"])
                XCTAssertEqual(actual, text, "\(locale), count \(count)")
            }
        }
    }

    // MARK: Helpers

    /// The compiled plural keys of `locale` that some Baseline locale had as a counted phrase but
    /// `locale`'s Baseline did not. A key no Baseline locale had is a counted phrase added since and
    /// is not held to the Baseline.
    static func variantsTheBaselineLacked(_ compiled: [String], in locale: String,
                                          _ baseline: [String: [String]]) -> [String] {
        let counted = baseline.values.reduce(into: Set<String>()) { $0.formUnion($1) }
        let allowed = Set(baseline[locale] ?? [])
        return compiled.filter { counted.contains($0) && !allowed.contains($0) }.sorted()
    }

    private func format(_ phrase: Phrase, arguments: [Argument], in bundle: Bundle, locale: String) throws -> String {
        let values = zip(phrase.types, arguments).map { type, argument -> CVarArg in
            switch (type, argument) {
            case ("int", .number(let value)): return Int(value)
            case ("uint", .number(let value)): return UInt(value)
            case ("double", .number(let value)): return value
            case (_, .text(let value)): return value
            default: return "\(argument)"
            }
        }
        if phrase.interpolated {
            return try String(localized: interpolation(phrase.key, values),
                              table: "Localizable",
                              bundle: bundle,
                              locale: Locale(identifier: locale))
        }
        let template = bundle.localizedString(forKey: phrase.key, value: nil, table: "Localizable")
        return String(format: template, locale: Locale(identifier: locale), arguments: values)
    }

    /// The localization value `String(localized: "…\(value)…")` builds, for a key the compiler derived.
    private func interpolation(_ key: String, _ values: [CVarArg]) throws -> String.LocalizationValue {
        let regex = try NSRegularExpression(pattern: "%%|%(lld|llu|@|lf|f)")
        var result = String.LocalizationValue.StringInterpolation(
            literalCapacity: key.count,
            interpolationCount: values.count
        )
        var next = key.startIndex
        var remaining = values.makeIterator()
        for match in regex.matches(in: key, range: NSRange(key.startIndex..., in: key)) {
            guard let range = Range(match.range, in: key) else { continue }
            result.appendLiteral(String(key[next..<range.lowerBound]))
            next = range.upperBound
            if key[range] == "%%" {
                result.appendLiteral("%")
                continue
            }
            switch remaining.next() {
            case let value as Int: result.appendInterpolation(value)
            case let value as UInt: result.appendInterpolation(value)
            case let value as Double: result.appendInterpolation(value)
            case let value as String: result.appendInterpolation(value)
            default: XCTFail("\(key): more codes than arguments")
            }
        }
        result.appendLiteral(String(key[next...]))
        return String.LocalizationValue(stringInterpolation: result)
    }

    private func loadFixture() throws -> Fixture {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "BaselinePluralForms", withExtension: "json"),
                                "BaselinePluralForms.json is not in the test bundle")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    private func localization(_ locale: String) throws -> Bundle {
        let path = try XCTUnwrap(Bundle.main.path(forResource: locale, ofType: "lproj"),
                                 "the app bundle has no \(locale).lproj")
        return try XCTUnwrap(Bundle(path: path))
    }
}
