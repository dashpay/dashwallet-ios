import Foundation
import XCTest
@testable import LocalizationCodemod

/// T4 rules (AC-08). Leftover reasons: `fixed-precision float`, `argument mismatch`, and, for a formatted key
/// not wrapped in `String(format:)` / `String.localizedStringWithFormat`, T3's `format code in key (T4)` (kept).
/// A `String(format:)` around a variable or non-literal format is not a lookup: untouched, no leftover.
/// A rewritten multi-line `String(format:)` call collapses to one `String(localized: "…", comment: c)` line.
final class FormattedLookupTests: XCTestCase {
    private func check(_ input: String, _ expected: String, leftovers: [Leftover] = [],
                       keep: Set<String> = [],
                       file: StaticString = #filePath, line: UInt = #line) {
        let result = rewrite(source: input, path: "A.swift", keepLiteralKeys: keep)
        XCTAssertEqual(result.output, expected, file: file, line: line)
        XCTAssertEqual(result.leftovers, leftovers, file: file, line: line)
        let again = rewrite(source: result.output, path: "A.swift", keepLiteralKeys: keep)
        XCTAssertEqual(again.output, result.output, file: file, line: line)
        XCTAssertEqual(again.leftovers, leftovers, file: file, line: line)
    }

    private func left(_ reason: String, line: Int = 1) -> Leftover {
        Leftover(path: "A.swift", line: line, reason: reason)
    }

    func testStringFormatBecomesInterpolation() {
        check(#"let a = String(format: NSLocalizedString("zz %d items", comment: "c"), n)"#,
              #"let a = String(localized: "zz \(n) items", comment: "c")"#)
    }

    func testLocalizedStringWithFormatBecomesInterpolation() {
        check(#"let a = String.localizedStringWithFormat(NSLocalizedString("zz %@ of %d", comment: "c"), a, b)"#,
              #"let a = String(localized: "zz \(a) of \(b)", comment: "c")"#)
    }

    func testPositionalCodesInOrder() {
        check(#"let a = String(format: NSLocalizedString("zz %1$d of %2$@", comment: "c"), n, s)"#,
              #"let a = String(localized: "zz \(n) of \(s)", comment: "c")"#)
    }

    func testSwappedPositionalCodesFollowEnglishOrder() {
        check(#"let a = String(format: NSLocalizedString("zz %2$@ has %1$d", comment: "c"), n, s)"#,
              #"let a = String(localized: "zz \(s) has \(n)", comment: "c")"#)
    }

    func testDoublePercentBecomesLiteralPercent() {
        check(#"let a = String(format: NSLocalizedString("SPV: %@ (%d%%)", comment: "c"), s, p)"#,
              #"let a = String(localized: "SPV: \(s) (\(p)%)", comment: "c")"#)
    }

    func testComplexArgumentsAreInterpolatedVerbatim() {
        check(#"let a = String(format: NSLocalizedString("zz %d of %@", comment: "c"), Int((x * 100).rounded()), items.map { $0.done }.joined())"#,
              #"let a = String(localized: "zz \(Int((x * 100).rounded())) of \(items.map { $0.done }.joined())", comment: "c")"#)
    }

    func testMultiLineStringFormatCollapsesToOneLine() {
        let input = """
        func f() {
            let a = String(
                format: NSLocalizedString(
                    "zz %@ at %d",
                    comment: "c"
                ),
                name,
                count
            )
        }
        """
        let expected = """
        func f() {
            let a = String(localized: "zz \\(name) at \\(count)", comment: "c")
        }
        """
        check(input, expected)
    }

    func testCountedPhraseFollowsTheSameRule() {
        check(#"label.text = String(format: NSLocalizedString("zz %d contacts", comment: "plural"), contacts.count)"#,
              #"label.text = String(localized: "zz \(contacts.count) contacts", comment: "plural")"#)
    }

    func testFixedPrecisionFloatIsLeftAndListed() {
        for code in ["%.0f", "%.2f"] {
            let src = "let a = String(format: NSLocalizedString(\"zz \(code)\", comment: \"c\"), x)"
            check(src, src, leftovers: [left("fixed-precision float")])
        }
    }

    func testArgumentCountMismatchIsLeftAndListed() {
        let few = #"let a = String(format: NSLocalizedString("zz %d and %d", comment: "c"), n)"#
        check(few, few, leftovers: [left("argument mismatch")])
        let many = #"let a = String(format: NSLocalizedString("zz %d", comment: "c"), n, m)"#
        check(many, many, leftovers: [left("argument mismatch")])
    }

    func testVariableOrNonLiteralFormatIsUntouchedAndSilent() {
        check("let a = String(format: fmt, n)", "let a = String(format: fmt, n)")
        check(#"let a = String(format: "zz %d", n)"#, #"let a = String(format: "zz %d", n)"#)
        check(#"let a = String(format: "zz " + suffix, n)"#, #"let a = String(format: "zz " + suffix, n)"#)
    }

    func testKeepLiteralKeyKeepsFormattingCall() {
        check(#"let a = String(format: NSLocalizedString("zz %@", comment: "c"), s)"#,
              #"let a = String(format: String(localized: "zz %@", comment: "c"), s)"#,
              keep: ["zz %@"])
        check(#"let a = String.localizedStringWithFormat(NSLocalizedString("zz %d", comment: "c"), n)"#,
              #"let a = String.localizedStringWithFormat(String(localized: "zz %d", comment: "c"), n)"#,
              keep: ["zz %d"])
    }

    func testKeepLiteralPlainKeyStillBecomesLocalized() {
        check(#"let a = NSLocalizedString("zz.alpha", comment: "c")"#,
              #"let a = String(localized: "zz.alpha", comment: "c")"#,
              keep: ["zz.alpha"])
    }

    func testKeepLiteralWinsOverFixedPrecisionAndMismatch() {
        check(#"let a = String(format: NSLocalizedString("zz %.2f", comment: "c"), x)"#,
              #"let a = String(format: String(localized: "zz %.2f", comment: "c"), x)"#,
              keep: ["zz %.2f"])
    }

    func testFormattedKeyOutsideAFormattingCallIsListed() {
        let src = #"let fmt = NSLocalizedString("zz %@", comment: "c")"#
        check(src, src, leftovers: [left("format code in key (T4)")])
    }

    func testMixedFileRewritesWhatItCanAndListsTheRest() {
        let input = """
        let a = String(format: NSLocalizedString("zz %d", comment: "c"), n)
        let b = String(format: NSLocalizedString("zz %.1f", comment: "c"), x)
        let c = NSLocalizedString("zz.plain", comment: "c")
        """
        let expected = """
        let a = String(localized: "zz \\(n)", comment: "c")
        let b = String(format: NSLocalizedString("zz %.1f", comment: "c"), x)
        let c = String(localized: "zz.plain", comment: "c")
        """
        check(input, expected, leftovers: [left("fixed-precision float", line: 2)])
    }
}
