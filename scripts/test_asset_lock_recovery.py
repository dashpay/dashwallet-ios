#!/usr/bin/env python3
"""Test the production resume entry point and durable probe store in isolation."""
from pathlib import Path
import os
import subprocess
import tempfile

repository = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="asset-lock-recovery-tests-") as directory:
    package = Path(directory)
    source = package / "Sources/RecoveryHarness"
    tests = package / "Tests/RecoveryHarnessTests"
    source.mkdir(parents=True)
    tests.mkdir(parents=True)
    (source / "AssetLockProbeStore.swift").symlink_to(repository / "DashWallet/Sources/Infrastructure/SwiftDashSDK/AssetLockProbeStore.swift")
    production = (repository / "DashWallet/Sources/UI/Payments/InternalTransfer/Shielded/ShieldedTransferCoordinator.swift").read_text()
    methods = []
    for marker in ("    func resumeAssetLock(", "    static func alreadyConsumedAssetLockResumePhase("):
        start = production.index(marker)
        opening = production.index("{", start)
        depth, end = 1, opening + 1
        while depth:
            depth += (production[end] == "{") - (production[end] == "}")
            end += 1
        methods.append(production[start:end])
    harness = (repository / "scripts/fixtures/AssetLockRecoveryHarness.swift").read_text()
    (source / "Coordinator.swift").write_text(harness.replace("// PRODUCTION_METHODS", "\n".join(methods)))
    (tests / "RecoveryTests.swift").symlink_to(repository / "scripts/fixtures/AssetLockRecoveryTests.swift")
    (package / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "RecoveryHarness", platforms: [.macOS("15.0")], targets: [
    .target(name: "RecoveryHarness"),
    .testTarget(name: "RecoveryHarnessTests", dependencies: ["RecoveryHarness"])
])
''')
    environment = os.environ.copy()
    environment["CLANG_MODULE_CACHE_PATH"] = str(package / "modules")
    environment["SWIFTPM_MODULECACHE_OVERRIDE"] = str(package / "modules")
    subprocess.run(["xcrun", "swift", "test", "--package-path", str(package),
                    "--scratch-path", str(package / ".build"), "--cache-path", str(package / "cache"),
                    "--config-path", str(package / "configuration"), "--security-path", str(package / "security"),
                    "--disable-sandbox"], check=True, env=environment)
