import Foundation
import LocalizationCodemod

var roots = Array(CommandLine.arguments.dropFirst())
let dryRun = roots.contains("--dry-run")

roots.removeAll { $0 == "--dry-run" }

do {
    for line in try runCodemod(roots: roots, dryRun: dryRun) {
        print(line)
    }
} catch {
    print("codemod: \(error)")
    exit(1)
}
