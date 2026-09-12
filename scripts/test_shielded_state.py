#!/usr/bin/env python3
"""Run production shielded state controllers and their XCTest suites without iOS/FFI."""
from pathlib import Path
import os
import subprocess
import tempfile

repository = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="shielded-state-tests-") as directory:
    package = Path(directory)
    sources = package / "Sources" / "ShieldedBalanceHarness"
    tests = package / "Tests" / "ShieldedBalanceHarnessTests"
    sources.mkdir(parents=True)
    tests.mkdir(parents=True)
    for name in ["ShieldedBalanceController", "ShieldedRecoveryController"]:
        source = repository / "DashWallet/Sources/Infrastructure/SwiftDashSDK" / (name + ".swift")
        test = repository / "DashWalletTests" / (name + "Tests.swift")
        if source.exists():
            (sources / source.name).symlink_to(source)
            (tests / test.name).symlink_to(test)
    (package / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "ShieldedBalanceHarness", platforms: [.macOS(.v13)], targets: [
    .target(name: "ShieldedBalanceHarness"),
    .testTarget(name: "ShieldedBalanceHarnessTests", dependencies: ["ShieldedBalanceHarness"])
])
''')
    environment = os.environ.copy()
    environment["CLANG_MODULE_CACHE_PATH"] = str(package / "modules")
    environment["SWIFTPM_MODULECACHE_OVERRIDE"] = str(package / "modules")
    subprocess.run(["xcrun", "swift", "test", "--package-path", str(package),
                    "--scratch-path", str(package / ".build"), "--cache-path", str(package / "cache"),
                    "--config-path", str(package / "configuration"), "--security-path", str(package / "security"),
                    "--disable-sandbox"], check=True, env=environment)
