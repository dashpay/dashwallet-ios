#!/usr/bin/env python3
"""Run balance/recovery tests; --sdk-path also exercises real SwiftData models."""
from pathlib import Path
import argparse
import json
import os
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--sdk-path", type=Path, help="Local SwiftDashSDK package with a macOS framework slice")
args = parser.parse_args()
repository = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="shielded-state-tests-") as directory:
    package = Path(directory)
    sources = package / "Sources" / "ShieldedBalanceHarness"
    tests = package / "Tests" / "ShieldedBalanceHarnessTests"
    sources.mkdir(parents=True)
    tests.mkdir(parents=True)
    names = ["ShieldedBalanceController", "ShieldedRecoveryController", "PlatformBalanceController", "HomeBalancePresentation"]
    if args.sdk_path:
        names.append("PlatformBalanceReader")
    for name in names:
        source = repository / "DashWallet/Sources/Infrastructure/SwiftDashSDK" / (name + ".swift")
        test = repository / "DashWalletTests" / (name + "Tests.swift")
        for path in (source, test):
            if not path.is_file():
                raise SystemExit(f"missing expected file: {path}")
        (sources / source.name).symlink_to(source)
        (tests / test.name).symlink_to(test)
    sdk_dependency = f'.package(path: {json.dumps(str(args.sdk_path.resolve()))})' if args.sdk_path else ""
    target_dependency = '.product(name: "SwiftDashSDK", package: "swift-sdk")' if args.sdk_path else ""
    manifest = '''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "ShieldedBalanceHarness", platforms: [.macOS("15.0")],
    dependencies: [SDK_DEPENDENCY], targets: [
    .target(name: "ShieldedBalanceHarness", dependencies: [TARGET_DEPENDENCY]),
    .testTarget(name: "ShieldedBalanceHarnessTests", dependencies: ["ShieldedBalanceHarness"])
])
'''
    (package / "Package.swift").write_text(manifest.replace("SDK_DEPENDENCY", sdk_dependency).replace("TARGET_DEPENDENCY", target_dependency))
    environment = os.environ.copy()
    environment["CLANG_MODULE_CACHE_PATH"] = str(package / "modules")
    environment["SWIFTPM_MODULECACHE_OVERRIDE"] = str(package / "modules")
    subprocess.run(["xcrun", "swift", "test", "--package-path", str(package),
                    "--scratch-path", str(package / ".build"), "--cache-path", str(package / "cache"),
                    "--config-path", str(package / "configuration"), "--security-path", str(package / "security"),
                    "--disable-sandbox"], check=True, env=environment)
