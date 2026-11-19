import Foundation
import XCTest
@testable import LocalizationCodemod

/// Leftover format (cli.md has no codemod section; the T3 brief sets it): one line per place,
/// `<path>:<line>: <reason>`, sorted by path then line. Reasons: `non-literal key`,
/// `unsupported argument: <label>:` for tableName/bundle/value, `format code in key (T4)` for formatted keys.
final class CodemodTests: XCTestCase {
    private func check(_ input: String, _ expected: String, leftovers: [Leftover] = [],
                       file: StaticString = #filePath, line: UInt = #line) {
        let result = rewrite(source: input, path: "A.swift")
        XCTAssertEqual(result.output, expected, file: file, line: line)
        XCTAssertEqual(result.leftovers, leftovers, file: file, line: line)
        // Second run: nothing changes, nothing new is listed for rewritten places.
        let again = rewrite(source: result.output, path: "A.swift")
        XCTAssertEqual(again.output, result.output, file: file, line: line)
        XCTAssertEqual(again.leftovers, leftovers, file: file, line: line)
    }

    func testPlainCallKeepsKeyAndComment() {
        check(#"let a = NSLocalizedString("zz.alpha", comment: "Alpha note")"#,
              #"let a = String(localized: "zz.alpha", comment: "Alpha note")"#)
    }

    func testEmptyComment() {
        check(#"let a = NSLocalizedString("zz.alpha", comment: "")"#,
              #"let a = String(localized: "zz.alpha", comment: "")"#)
    }

    func testMultiLineCallKeepsLinesAndIndentation() {
        let input = """
        func f() {
            let a = NSLocalizedString(
                "zz.alpha",
                comment: "Alpha note"
            )
        }
        """
        let expected = """
        func f() {
            let a = String(
                localized: "zz.alpha",
                comment: "Alpha note"
            )
        }
        """
        check(input, expected)
    }

    func testEscapedKeysKeepTheirLiteralText() {
        let literals = [
            #""zz.\"quoted\"""#,
            #""zz.line\nbreak""#,
            #""zz.\u{00E9}clair""#,
            ##"#"zz.raw \n "quote""#"##,
            "\"\"\"\n    zz.multi\n    line\n    \"\"\"",
        ]
        for literal in literals {
            check("let a = NSLocalizedString(\(literal), comment: \"c\")",
                  "let a = String(localized: \(literal), comment: \"c\")")
        }
    }

    func testFormattedKeyIsLeftForT4AndListed() {
        for key in ["zz.%@", "zz.%d", "zz.%1$d of %2$@", "zz.100%%", "zz.%.2f"] {
            let src = "let a = NSLocalizedString(\"\(key)\", comment: \"c\")"
            check(src, src, leftovers: [Leftover(path: "A.swift", line: 1, reason: "format code in key (T4)")])
        }
    }

    func testNonLiteralKeyIsListed() {
        let src = "let a = NSLocalizedString(key, comment: \"\")"
        check(src, src, leftovers: [Leftover(path: "A.swift", line: 1, reason: "non-literal key")])
    }

    func testUnsupportedArgumentsAreListed() {
        let cases: [(String, String)] = [
            (#"NSLocalizedString("zz.a", tableName: "T", comment: "c")"#, "tableName"),
            (#"NSLocalizedString("zz.a", bundle: .main, comment: "c")"#, "bundle"),
            (#"NSLocalizedString("zz.a", value: "v", comment: "c")"#, "value"),
        ]
        for (call, label) in cases {
            let src = "\nlet a = \(call)"
            check(src, src, leftovers: [Leftover(path: "A.swift", line: 2, reason: "unsupported argument: \(label):")])
        }
    }

    func testCallsInCommentsAreIgnored() {
        let src = """
        // let a = NSLocalizedString("zz.alpha", comment: "c")
        /* let b = NSLocalizedString("zz.beta", comment: "c")
           NSLocalizedString(key, comment: "") */
        let c = 1
        """
        check(src, src)
    }

    func testMixedFileRewritesOnlyPlainCalls() {
        let input = """
        let a = NSLocalizedString("zz.alpha", comment: "c")
        let b = NSLocalizedString(key, comment: "c")
        let c = NSLocalizedString("zz.gamma", comment: "c")
        """
        let expected = """
        let a = String(localized: "zz.alpha", comment: "c")
        let b = NSLocalizedString(key, comment: "c")
        let c = String(localized: "zz.gamma", comment: "c")
        """
        check(input, expected, leftovers: [Leftover(path: "A.swift", line: 2, reason: "non-literal key")])
    }

    // MARK: scope

    func testRunTouchesOnlyAppAndTestSwiftFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("codemod-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let old = "let a = NSLocalizedString(\"zz.alpha\", comment: \"c\")\n"
        let new = "let a = String(localized: \"zz.alpha\", comment: \"c\")\n"
        let files = [
            "DashWallet/Sources/A.swift": true,
            "DashWalletTests/B.swift": true,
            "WatchApp/C.swift": false,
            "WatchApp Extension/D.swift": false,
            "Pods/Lib/E.swift": false,
            "DashWallet/Sources/F.m": false,
            "DashWallet/Sources/G.txt": false,
        ]
        for path in files.keys {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try old.write(to: url, atomically: true, encoding: .utf8)
        }
        let leftovers = try runCodemod(roots: [root.path])
        XCTAssertEqual(leftovers, [])
        for (path, rewritten) in files {
            let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            XCTAssertEqual(text, rewritten ? new : old, path)
        }
    }

    func testRunLeftoversAreSortedByPathThenLine() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("codemod-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("DashWallet")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let body = "let a = 1\nlet b = NSLocalizedString(key, comment: \"\")\nlet c = NSLocalizedString(key2, comment: \"\")\n"
        try body.write(to: dir.appendingPathComponent("B.swift"), atomically: true, encoding: .utf8)
        try body.write(to: dir.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8)
        let lines = try runCodemod(roots: [root.path])
        XCTAssertEqual(lines, [
            "\(root.path)/DashWallet/A.swift:2: non-literal key",
            "\(root.path)/DashWallet/A.swift:3: non-literal key",
            "\(root.path)/DashWallet/B.swift:2: non-literal key",
            "\(root.path)/DashWallet/B.swift:3: non-literal key",
        ])
    }
}
