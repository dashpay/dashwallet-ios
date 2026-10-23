#!/usr/bin/env python3
"""Run the existing production fee-cache tests separately from protocol notices."""
from pathlib import Path
import os
import subprocess
import tempfile

repository = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="core-shielded-fee-tests-") as directory:
    package = Path(directory)
    source = package / "Sources/CoreToShieldedFeeHarness"
    tests = package / "Tests/CoreToShieldedFeeHarnessTests"
    source.mkdir(parents=True)
    tests.mkdir(parents=True)
    (source / "Harness.swift").symlink_to(
        repository / "scripts/fixtures/CoreToShieldedFeeCompatibilityHarness.swift")
    (tests / "Tests.swift").symlink_to(
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
let package = Package(name: "CoreToShieldedFeeHarness", platforms: [.macOS("15.0")], targets: [
    .target(name: "CoreToShieldedFeeHarness"),
    .testTarget(name: "CoreToShieldedFeeHarnessTests", dependencies: ["CoreToShieldedFeeHarness"])
])
''')
    environment = os.environ.copy()
    environment["CLANG_MODULE_CACHE_PATH"] = str(package / "modules")
    environment["SWIFTPM_MODULECACHE_OVERRIDE"] = str(package / "modules")
    subprocess.run(["xcrun", "swift", "test", "--package-path", str(package),
                    "--scratch-path", str(package / ".build"), "--cache-path", str(package / "cache"),
                    "--config-path", str(package / "configuration"), "--security-path", str(package / "security"),
                    "--disable-sandbox"], check=True, env=environment)
