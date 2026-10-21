#!/usr/bin/env python3
"""Run production compatibility lifecycle, banner, and fee-cache logic offline."""
from pathlib import Path
import argparse
import os
import subprocess
import tempfile

repository = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--testflight", action="store_true", help="Test TestFlight update guidance")
arguments = parser.parse_args()
with tempfile.TemporaryDirectory(prefix="protocol-compatibility-tests-") as directory:
    package = Path(directory)
    source = package / "Sources/ProtocolCompatibilityHarness"
    tests = package / "Tests/ProtocolCompatibilityHarnessTests"
    source.mkdir(parents=True)
    tests.mkdir(parents=True)
    (source / "WalletProtocolCompatibilityController.swift").symlink_to(
        repository / "DashWallet/Sources/Infrastructure/SwiftDashSDK/WalletProtocolCompatibilityController.swift")
    (source / "ProtocolCompatibilityBanner.swift").symlink_to(
        repository / "DashWallet/Sources/UI/Main/ProtocolCompatibilityBanner.swift")
    (tests / "WalletProtocolCompatibilityTests.swift").symlink_to(
        repository / "DashWalletTests/WalletProtocolCompatibilityTests.swift")
    (source / "CoreToShieldedFeeCompatibilityHarness.swift").symlink_to(
        repository / "scripts/fixtures/CoreToShieldedFeeCompatibilityHarness.swift")
    (tests / "CoreToShieldedFeeCompatibilityTests.swift").symlink_to(
        repository / "scripts/fixtures/CoreToShieldedFeeCompatibilityTests.swift")
    production = (repository / "DashWallet/Sources/UI/Payments/InternalTransfer/InternalTransferViewModel.swift").read_text()
    start = production.index("@MainActor\nenum CoreToShieldedAmountPolicy {")
    opening = production.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (production[end] == "{") - (production[end] == "}")
        end += 1
    (source / "CoreToShieldedAmountPolicy.swift").write_text(production[start:end] + "\n")
    (package / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "ProtocolCompatibilityHarness", platforms: [.macOS("15.0")], targets: [
    .target(name: "ProtocolCompatibilityHarness"),
    .testTarget(name: "ProtocolCompatibilityHarnessTests", dependencies: ["ProtocolCompatibilityHarness"])
])
''')
    environment = os.environ.copy()
    environment["CLANG_MODULE_CACHE_PATH"] = str(package / "modules")
    environment["SWIFTPM_MODULECACHE_OVERRIDE"] = str(package / "modules")
    subprocess.run(["xcrun", "swift", "test", "--package-path", str(package),
                    "--scratch-path", str(package / ".build"), "--cache-path", str(package / "cache"),
                    "--config-path", str(package / "configuration"), "--security-path", str(package / "security"),
                    "--disable-sandbox"] + (["-Xswiftc", "-DTESTFLIGHT"] if arguments.testflight else []),
                   check=True, env=environment)
