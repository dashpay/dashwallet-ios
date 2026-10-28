#!/usr/bin/env python3
"""Exercise the production two-leg top-up with deterministic SDK refusals."""
from pathlib import Path
import os
import subprocess
import tempfile

repository = Path(__file__).resolve().parents[1]
production = (repository / "DashWallet/Sources/UI/DashPay/Profile/SDKIdentityProfileSheet.swift").read_text()


def declaration(marker):
    start = production.index(marker)
    opening = production.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (production[end] == "{") - (production[end] == "}")
        end += 1
    return production[start:end].replace("private func", "func", 1)


with tempfile.TemporaryDirectory(prefix="identity-top-up-compatibility-") as directory:
    package = Path(directory)
    source = package / "Sources/IdentityTopUpHarness"
    tests = package / "Tests/IdentityTopUpHarnessTests"
    source.mkdir(parents=True)
    tests.mkdir(parents=True)
    # The production control flow and error classification are unchanged.
    # Only the native SDK, persistence, and address-provider boundaries are fakes.
    methods = "\n".join(declaration(marker) for marker in (
        "    func topUp(",
        "    enum TopUpError: LocalizedError {",
        "    private func topUpFromShielded(",
    ))
    scaffold = (repository / "scripts/fixtures/IdentityTopUpCompatibilityHarness.swift").read_text()
    sentinel = "    // PRODUCTION_TOP_UP"
    assert scaffold.count(sentinel) == 1
    (source / "IdentityTopUpHarness.swift").write_text(scaffold.replace(sentinel, methods))
    (tests / "IdentityTopUpCompatibilityTests.swift").symlink_to(
        repository / "scripts/fixtures/IdentityTopUpCompatibilityTests.swift")
    (package / "Package.swift").write_text("""// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "IdentityTopUpHarness", platforms: [.macOS("15.0")], targets: [
    .target(name: "IdentityTopUpHarness"),
    .testTarget(name: "IdentityTopUpHarnessTests", dependencies: ["IdentityTopUpHarness"])
])
""")
    environment = os.environ.copy()
    environment["CLANG_MODULE_CACHE_PATH"] = str(package / "modules")
    environment["SWIFTPM_MODULECACHE_OVERRIDE"] = str(package / "modules")
    subprocess.run([
        "xcrun", "swift", "test", "--package-path", str(package),
        "--scratch-path", str(package / ".build"), "--cache-path", str(package / "cache"),
        "--config-path", str(package / "configuration"), "--security-path", str(package / "security"),
        "--disable-sandbox",
    ], check=True, env=environment)
