#!/usr/bin/env python3
"""Run the real Core drain marker store against isolated temporary files."""
from pathlib import Path
import subprocess
import tempfile

repository = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="core-drain-tests-") as temporary:
    package = Path(temporary)
    sources = package / "Sources/CoreDrainHarness"
    tests = package / "Tests/CoreDrainHarnessTests"
    sources.mkdir(parents=True)
    tests.mkdir(parents=True)
    source = repository / "DashWallet/Sources/UI/Payments/InternalTransfer/Shielded/CoreShieldedDrainStore.swift"
    test = repository / "DashWalletTests/CoreShieldedDrainStoreTests.swift"
    (sources / source.name).symlink_to(source)
    (tests / test.name).symlink_to(test)
    (package / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "CoreDrainHarness", platforms: [.macOS("15.0")], targets: [
    .target(name: "CoreDrainHarness"),
    .testTarget(name: "CoreDrainHarnessTests", dependencies: ["CoreDrainHarness"])
])
''')
    subprocess.run(["xcrun", "swift", "test", "--package-path", str(package), "--disable-sandbox"], check=True)
