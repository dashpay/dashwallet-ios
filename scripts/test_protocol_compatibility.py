#!/usr/bin/env python3
"""Run actual advisory controller, banner and SDK model sources without native FFI."""
from pathlib import Path
import argparse
import subprocess
import tempfile

repository = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--testflight", action="store_true")
args = parser.parse_args()
with tempfile.TemporaryDirectory(prefix="protocol-observation-") as directory:
    package = Path(directory)
    source = package / "Sources/dashpay"
    sdk = package / "Sources/SwiftDashSDK"
    tests = package / "Tests/ProtocolTests"
    for folder in (source, sdk, tests):
        folder.mkdir(parents=True)
    for path in (
        "DashWallet/Sources/Infrastructure/SwiftDashSDK/WalletProtocolCompatibilityController.swift",
        "DashWallet/Sources/UI/Main/ProtocolCompatibilityBanner.swift",
    ):
        (source / Path(path).name).symlink_to(repository / path)
    (sdk / "ProtocolVersionInfo.swift").symlink_to(
        repository.parent / "platform/packages/swift-sdk/Sources/SwiftDashSDK/ProtocolVersionInfo.swift")
    (tests / "WalletProtocolCompatibilityTests.swift").symlink_to(
        repository / "DashWalletTests/WalletProtocolCompatibilityTests.swift")
    (package / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "ProtocolObservation", platforms: [.macOS("15.0")], targets: [
    .target(name: "SwiftDashSDK"),
    .target(name: "dashpay", dependencies: ["SwiftDashSDK"]),
    .testTarget(name: "ProtocolTests", dependencies: ["dashpay", "SwiftDashSDK"])
])
''')
    subprocess.run(["xcrun", "swift", "test", "--package-path", str(package), "--disable-sandbox"]
                   + (["-Xswiftc", "-DTestflight"] if args.testflight else []), check=True)
