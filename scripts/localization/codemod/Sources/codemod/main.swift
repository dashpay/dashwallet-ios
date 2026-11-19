import Foundation
import LocalizationCodemod

var arguments = Array(CommandLine.arguments.dropFirst())

let dryRun = arguments.contains("--dry-run")

arguments.removeAll { $0 == "--dry-run" }

var keepLiteralKeys: Set<String> = []

if let flag = arguments.firstIndex(of: "--keep-literal-keys") {
    guard flag + 1 < arguments.count else {
        print("codemod: --keep-literal-keys needs a file")
        exit(2)
    }
    do {
        let text = try String(contentsOfFile: arguments[flag + 1], encoding: .utf8)
        let lines = text.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
        keepLiteralKeys = Set(lines.filter { !$0.isEmpty })
    } catch {
        print("codemod: \(error)")
        exit(2)
    }
    arguments.removeSubrange(flag ... flag + 1)
}

do {
    for line in try runCodemod(roots: arguments, dryRun: dryRun, keepLiteralKeys: keepLiteralKeys) {
        print(line)
    }
} catch {
    print("codemod: \(error)")
    exit(1)
}
