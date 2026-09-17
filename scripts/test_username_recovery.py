#!/usr/bin/env python3
"""Run the production DPNS recovery policy tests without the app/SDK runtime."""
from pathlib import Path
import os
import subprocess
import tempfile

repository = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="username-recovery-tests-") as directory:
    package = Path(directory)
    source = package / "Sources/UsernameRecoveryHarness"
    tests = package / "Tests/UsernameRecoveryHarnessTests"
    source.mkdir(parents=True)
    tests.mkdir(parents=True)
    (source / "DWUsernameRegistrationRecovery.swift").symlink_to(
        repository / "DashWallet/Sources/Infrastructure/SwiftDashSDK/Identity/DWUsernameRegistrationRecovery.swift")
    (tests / "UsernameRegistrationRecoveryTests.swift").symlink_to(
        repository / "DashWalletTests/UsernameRegistrationRecoveryTests.swift")
    (package / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "UsernameRecoveryHarness", platforms: [.macOS("15.0")], targets: [
    .target(name: "UsernameRecoveryHarness"),
    .testTarget(name: "UsernameRecoveryHarnessTests", dependencies: ["UsernameRecoveryHarness"])
])
''')
    environment = os.environ.copy()
    environment["CLANG_MODULE_CACHE_PATH"] = str(package / "modules")
    environment["SWIFTPM_MODULECACHE_OVERRIDE"] = str(package / "modules")
    subprocess.run(["xcrun", "swift", "test", "--package-path", str(package),
                    "--scratch-path", str(package / ".build"), "--cache-path", str(package / "cache"),
                    "--config-path", str(package / "configuration"), "--security-path", str(package / "security"),
                    "--disable-sandbox"], check=True, env=environment)
