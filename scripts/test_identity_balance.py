#!/usr/bin/env python3
"""Run the production identity balance refresh tests without the app/SDK runtime."""
from pathlib import Path
import os
import subprocess
import tempfile

repository = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="identity-balance-tests-") as directory:
    package = Path(directory)
    source = package / "Sources/IdentityBalanceHarness"
    tests = package / "Tests/IdentityBalanceHarnessTests"
    source.mkdir(parents=True)
    tests.mkdir(parents=True)
    (source / "DWIdentityBalanceRefresh.swift").symlink_to(
        repository / "DashWallet/Sources/Infrastructure/SwiftDashSDK/Identity/DWIdentityBalanceRefresh.swift")
    (tests / "IdentityBalanceRefreshTests.swift").symlink_to(
        repository / "DashWalletTests/IdentityBalanceRefreshTests.swift")
    # Compile the actual coordinator completion block against small app/SDK
    # stand-ins. This tests its production ordering, including where the Task
    # is created, rather than a separately reimplemented scheduling helper.
    coordinator = (repository / "DashWallet/Sources/Infrastructure/SwiftDashSDK/Identity/DWIdentityRegistrationCoordinator.swift").read_text()
    completion = coordinator.split(
        "            _ = try? await wallet.syncDpnsNames(identityId: identityId)\n        }\n", 1)[1]
    completion = completion.split("\n    }", 1)[0]
    scaffold = (repository / "scripts/fixtures/IdentityRegistrationCompletionHarness.swift").read_text()
    (source / "IdentityRegistrationCompletionHarness.swift").write_text(
        scaffold.replace("        // PRODUCTION_COMPLETION_BLOCK", completion))
    (package / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "IdentityBalanceHarness", platforms: [.macOS("15.0")], targets: [
    .target(name: "IdentityBalanceHarness"),
    .testTarget(name: "IdentityBalanceHarnessTests", dependencies: ["IdentityBalanceHarness"])
])
''')
    environment = os.environ.copy()
    environment["CLANG_MODULE_CACHE_PATH"] = str(package / "modules")
    environment["SWIFTPM_MODULECACHE_OVERRIDE"] = str(package / "modules")
    subprocess.run(["xcrun", "swift", "test", "--package-path", str(package),
                    "--scratch-path", str(package / ".build"), "--cache-path", str(package / "cache"),
                    "--config-path", str(package / "configuration"), "--security-path", str(package / "security"),
                    "--disable-sandbox"], check=True, env=environment)
