#!/usr/bin/env python3
"""Run production SPV rebuild marker tests, including awaited native starts."""
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
base = repo / "DashWallet/Sources/Infrastructure/SwiftDashSDK"


def declaration(file, marker):
    text = (base / file).read_text()
    start = text.index(marker)
    end = text.index("{", start) + 1
    depth = 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start:end]


with tempfile.TemporaryDirectory(prefix="spv-start-rebuild-tests-") as directory:
    root = Path(directory)
    sources = root / "Sources/SPVRebuildHarness"
    tests = root / "Tests/SPVRebuildHarnessTests"
    sources.mkdir(parents=True)
    tests.mkdir(parents=True)
    for file in ["SPVChainStoreRebuild.swift", "DurableFileStorage.swift"]:
        (sources / file).symlink_to(base / file)
    declarations = [
        declaration("WalletLocalStoreResetter.swift", "struct WalletLocalStoreRoots:"),
        declaration("WalletLocalStoreResetter.swift", "enum DurableMarkerFile {"),
    ]
    # Only diagnostic formatting/output are substituted; marker storage,
    # durability and all test bodies are production code.
    (sources / "Dependencies.swift").write_text("import Foundation\n" + "\n".join(declarations) + '''
enum DWLogger { static func log(_ message: String) { print(message) } }
struct WalletPreparationFailure {
    let codes: [String]
    init(error: Error) {
        let error = error as NSError
        codes = ["\\(error.domain):\\(error.code)"]
    }
}
''')
    production_tests = (repo / "DashWalletTests/SPVChainStoreRebuildTests.swift").read_text()
    (tests / "Tests.swift").write_text(production_tests.replace(
        "@testable import dashpay", "@testable import SPVRebuildHarness"))
    (root / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "SPVRebuildHarness", platforms: [.macOS("15.0")], targets: [
    .target(name: "SPVRebuildHarness"),
    .testTarget(name: "SPVRebuildHarnessTests", dependencies: ["SPVRebuildHarness"])
])
''')
    subprocess.run(["xcrun", "swift", "test", "--package-path", str(root), "--disable-sandbox"], check=True)
