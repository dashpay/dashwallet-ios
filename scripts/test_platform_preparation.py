#!/usr/bin/env python3
"""Test the host's actual local Platform preparation methods without an SDK runtime."""
from pathlib import Path
import os
import subprocess
import tempfile


repository = Path(__file__).resolve().parents[1]
host = (repository / "DashWallet/Sources/Infrastructure/SwiftDashSDK/SwiftDashSDKHost.swift").read_text()
start = host.index("    struct PlatformPreparation {")
end = host.index("    // MARK: - Wallet presence", start)
methods = host[start:end]
coordinator = (repository / "DashWallet/Sources/UI/Payments/InternalTransfer/Shielded/ShieldedTransferCoordinator.swift").read_text()

def coordinator_method(marker):
    start = coordinator.index(marker)
    end = coordinator.index('{', start) + 1
    depth = 1
    while depth:
        depth += (coordinator[end] == '{') - (coordinator[end] == '}')
        end += 1
    return coordinator[start:end]

controller = (repository / "DashWallet/Sources/Infrastructure/SwiftDashSDK/WalletProtocolCompatibilityController.swift").read_text()
error_start = controller.index("enum WalletOperationPreparationError:")
error_end = controller.index("\nprotocol WalletProtocolCompatibilityClient", error_start)

with tempfile.TemporaryDirectory(prefix="platform-preparation-tests-") as directory:
    package = Path(directory)
    source = package / "Sources/PlatformPreparationHarness"
    tests = package / "Tests/PlatformPreparationHarnessTests"
    source.mkdir(parents=True)
    tests.mkdir(parents=True)
    scaffold = (repository / "scripts/fixtures/PlatformPreparationHarness.swift").read_text()
    assert scaffold.count("// EXTRACTED_PRODUCTION_METHODS") == 1
    (source / "PlatformPreparationHarness.swift").write_text(
        scaffold.replace("// EXTRACTED_PRODUCTION_METHODS", methods)
        .replace("// RETRY_METHOD", coordinator_method("    func retryLastAssetLock("))
        .replace("// RESET_METHOD", coordinator_method("    func reset()"))
        + "\n" + controller[error_start:error_end] + "\n")
    (tests / "PlatformPreparationTests.swift").symlink_to(
        repository / "scripts/fixtures/PlatformPreparationTests.swift")
    (package / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "PlatformPreparationHarness", platforms: [.macOS("15.0")], targets: [
    .target(name: "PlatformPreparationHarness"),
    .testTarget(name: "PlatformPreparationHarnessTests", dependencies: ["PlatformPreparationHarness"])
])
''')
    environment = os.environ.copy()
    environment["CLANG_MODULE_CACHE_PATH"] = str(package / "modules")
    environment["SWIFTPM_MODULECACHE_OVERRIDE"] = str(package / "modules")
    subprocess.run([
        "xcrun", "swift", "test", "--package-path", str(package),
        "--scratch-path", str(package / ".build"), "--cache-path", str(package / "cache"),
        "--config-path", str(package / "configuration"), "--security-path", str(package / "security"),
        "--disable-sandbox",
    ], check=True, env=environment)
