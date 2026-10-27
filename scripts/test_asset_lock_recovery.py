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
    for marker in ("    func resumeAssetLock(", "    static func alreadyConsumedAssetLockResumePhase(",
                   "    func retryLastAssetLock(", "    func reset()", "    private func handleSpendError(",
                   "    private func handlePlatformSpendError("):
        start = production.index(marker)
        opening = production.index("{", start)
        depth, end = 1, opening + 1
        while depth:
            depth += (production[end] == "{") - (production[end] == "}")
            end += 1
        methods.append(production[start:end])
    harness = (repository / "scripts/fixtures/AssetLockRecoveryHarness.swift").read_text()
    def caller_method(path, marker):
        text = (repository / path).read_text()
        start = text.index(marker)
        end = text.index("{", start) + 1
        depth = 1
        while depth:
            depth += (text[end] == "{") - (text[end] == "}")
            end += 1
        return text[start:end].replace("private func", "func", 1)
    harness = harness.replace("// PRODUCTION_METHODS", "\n".join(methods))
    harness = harness.replace("// COINJOIN_RETRY", caller_method(
        "DashWallet/Sources/UI/Home/Views/CoinJoinMoveFunds/CoinJoinMoveFundsViewModel.swift",
        "    func retryShielded()"))
    harness = harness.replace("// COINJOIN_MOVE", caller_method(
        "DashWallet/Sources/UI/Home/Views/CoinJoinMoveFunds/CoinJoinMoveFundsViewModel.swift",
        "    func moveToShielded()"))
    harness = harness.replace("// COINJOIN_FINISH", caller_method(
        "DashWallet/Sources/UI/Home/Views/CoinJoinMoveFunds/CoinJoinMoveFundsViewModel.swift",
        "    private func finishFromCoordinatorPhase()"))
    harness = harness.replace("// SEND_RETRY", caller_method(
        "DashWallet/Sources/UI/Payments/Pay/SendScreen.swift", "    private func tryAgain()"))
    (source / "Coordinator.swift").write_text(harness)
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
