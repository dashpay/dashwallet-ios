#!/usr/bin/env python3
"""Run the real Core drain marker store against isolated temporary files."""
from pathlib import Path
import argparse
import subprocess
import tempfile
from core_drain_recovery_harness import write_recovery_harness

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--ios-simulator", metavar="UDID", help="Run in the iOS simulator sandbox")
args = parser.parse_args()

repository = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="core-drain-tests-") as temporary:
    package = Path(temporary)
    sources = package / "Sources/CoreDrainHarness"
    tests = package / "Tests/CoreDrainHarnessTests"
    sdk_stubs = package / "Sources/SwiftDashSDK"
    sources.mkdir(parents=True)
    tests.mkdir(parents=True)
    sdk_stubs.mkdir(parents=True)
    source = repository / "DashWallet/Sources/UI/Payments/InternalTransfer/Shielded/CoreShieldedDrainStore.swift"
    test = repository / "DashWalletTests/CoreShieldedDrainStoreTests.swift"
    (sources / source.name).symlink_to(source)
    durability = repository / "DashWallet/Sources/Infrastructure/SwiftDashSDK/DurableFileStorage.swift"
    (sources / durability.name).symlink_to(durability)
    (tests / test.name).symlink_to(test)
    write_recovery_harness(repository, sources, tests, sdk_stubs)
    (package / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "CoreDrainHarness", platforms: [.macOS("15.0"), .iOS("18.0")],
    products: [.library(name: "CoreDrainHarness", targets: ["CoreDrainHarness"])], targets: [
    .target(name: "SwiftDashSDK"),
    .target(name: "CoreDrainHarness", dependencies: ["SwiftDashSDK"]),
    .testTarget(name: "CoreDrainHarnessTests", dependencies: ["CoreDrainHarness", "SwiftDashSDK"])
])
''')
    if args.ios_simulator:
        subprocess.run([
            "xcodebuild", "-scheme", "CoreDrainHarness", "-sdk", "iphonesimulator",
            "-destination", f"platform=iOS Simulator,id={args.ios_simulator}",
            "-derivedDataPath", str(package / "DerivedData"), "ARCHS=arm64",
            "-parallel-testing-enabled", "NO", "test",
        ], cwd=package, check=True)
    else:
        subprocess.run(["xcrun", "swift", "test", "--package-path", str(package), "--disable-sandbox"], check=True)
