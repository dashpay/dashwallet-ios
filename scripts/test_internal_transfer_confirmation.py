#!/usr/bin/env python3
"""Run production confirmation and drain-resume decisions with controlled boundaries."""
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
base = repo / 'DashWallet/Sources/UI/Payments/InternalTransfer/Confirm'

def method(file, marker):
    text = (base / file).read_text()
    start = text.index(marker)
    end = text.index('{', start) + 1
    depth = 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]

with tempfile.TemporaryDirectory(prefix='transfer-confirmation-tests-') as temp:
    root = Path(temp)
    sources = root / 'Sources/ConfirmationHarness'
    tests = root / 'Tests/ConfirmationHarnessTests'
    sources.mkdir(parents=True)
    tests.mkdir(parents=True)
    runner = method('InternalTransferRunner.swift', '    func resumeCoreDrain(')
    confirm = method('InternalTransferConfirmViewModel.swift', '    func confirm()')
    scaffold = (repo / 'scripts/fixtures/InternalTransferConfirmationHarness.swift').read_text()
    (sources / 'Harness.swift').write_text(scaffold.replace('// RESUME_METHOD', runner).replace('// CONFIRM_METHOD', confirm))
    (tests / 'Tests.swift').symlink_to(repo / 'scripts/fixtures/InternalTransferConfirmationTests.swift')
    (root / 'Package.swift').write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "ConfirmationHarness", platforms: [.macOS("15.0")], targets: [
.target(name: "ConfirmationHarness"),
.testTarget(name: "ConfirmationHarnessTests", dependencies: ["ConfirmationHarness"])])
''')
    subprocess.run(['xcrun', 'swift', 'test', '--package-path', str(root), '--disable-sandbox'], check=True)
