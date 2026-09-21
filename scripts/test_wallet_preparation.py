#!/usr/bin/env python3
"""Exercise wallet-opening state and safe diagnostics without the legacy app test target."""
from pathlib import Path
import os
import subprocess
import tempfile

repository = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="wallet-preparation-tests-") as directory:
    package = Path(directory)
    sources = package / "Sources" / "WalletPreparationHarness"
    tests = package / "Tests" / "WalletPreparationHarnessTests"
    sources.mkdir(parents=True)
    tests.mkdir(parents=True)
    for name in ("WalletLifecycleTransitionState", "WalletPreparationFailure"):
        source = repository / "DashWallet/Sources/Infrastructure/SwiftDashSDK" / f"{name}.swift"
        test = repository / "DashWalletTests" / f"{name}Tests.swift"
        (sources / source.name).symlink_to(source)
        (tests / test.name).symlink_to(test)
    # Only unrelated app dependencies are substituted; state and diagnostics
    # are the production files, including their real Combine publishers.
    (sources / "AppDependencies.swift").write_text('''
enum WalletEnvironment { enum NetworkKind { case mainnet, testnet, devnet } }
enum DWLogger { static func log(_ message: String) {} }
''')
    (package / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "WalletPreparationHarness", platforms: [.macOS("15.0")], targets: [
    .target(name: "WalletPreparationHarness"),
    .testTarget(name: "WalletPreparationHarnessTests", dependencies: ["WalletPreparationHarness"])
])
''')
    environment = os.environ.copy()
    environment["CLANG_MODULE_CACHE_PATH"] = str(package / "modules")
    environment["SWIFTPM_MODULECACHE_OVERRIDE"] = str(package / "modules")
    subprocess.run(["xcrun", "swift", "test", "--package-path", str(package),
                    "--scratch-path", str(package / ".build"), "--cache-path", str(package / "cache"),
                    "--config-path", str(package / "configuration"), "--security-path", str(package / "security"),
                    "--disable-sandbox"], check=True, env=environment)
