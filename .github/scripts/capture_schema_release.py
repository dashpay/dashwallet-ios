#!/usr/bin/env python3
"""Capture SwiftData release evidence using the release checkout's iOS simulator slice."""

import argparse
import json
import pathlib
import re
import shutil
import subprocess
import tempfile


def run(*args, cwd=None):
    return subprocess.check_output(args, cwd=cwd, text=True).strip()


def extract_attachments(export_dir, output_dir):
    export_dir, output_dir = pathlib.Path(export_dir), pathlib.Path(output_dir)
    manifest = json.loads((export_dir / "manifest.json").read_text())
    for expected in ("schema.json", "fixture.store"):
        stem, extension = expected.rsplit(".", 1)
        # xcresulttool appends an ordinal and UUID to XCTest attachment names.
        name_pattern = re.compile(rf"{stem}(?:_[0-9]+_[A-Fa-f0-9-]+)?\.{extension}")
        matches = [
            item
            for test in manifest
            if "DashSchemaReleaseCaptureTests/testCaptureReleaseSchema" in test["testIdentifier"]
            for item in test["attachments"]
            if name_pattern.fullmatch(item["suggestedHumanReadableName"])
        ]
        if len(matches) != 1:
            raise ValueError(f"Expected one {expected} capture attachment, found {len(matches)}")
        source = (export_dir / matches[0]["exportedFileName"]).resolve()
        if source.parent != export_dir.resolve():
            raise ValueError("Invalid exported attachment path")
        shutil.copyfile(source, output_dir / expected)


def select_simulator(devices):
    candidates = []
    for runtime, items in devices.items():
        match = re.search(r"\.iOS-(\d+(?:-\d+){0,2})$", runtime)
        if not match:
            continue
        parts = tuple(int(part) for part in match[1].split("-"))
        version = parts + (0,) * (3 - len(parts))
        for device in items:
            if device.get("isAvailable") and device["name"].startswith("iPhone"):
                candidates.append((version, runtime, device))
    if not candidates:
        raise ValueError("No available iPhone simulator for schema capture")
    _, runtime, device = max(
        candidates, key=lambda item: (item[0], item[1], item[2]["name"], item[2]["udid"]))
    return runtime, device


def validate_capture_checkout(platform_dir):
    platform_dir = pathlib.Path(platform_dir).resolve()
    sdk = platform_dir / "packages/swift-sdk"
    required = ["schema-models.json", "scripts/freeze_schema_models.py"] + [
        f"SwiftTests/SwiftDashSDKTests/{name}.swift" for name in (
            "DashSchemaReleaseCaptureTests", "DashModelMigrationTests", "DashReleasedSchemaTests",
            "DashLegacySchemaMigrationTests")
    ]
    missing = [path for path in required if not (sdk / path).is_file()]
    if missing:
        raise ValueError("Selected Platform commit lacks schema capture support: " + ", ".join(missing))
    for path in required:
        run("git", "cat-file", "-e", f"HEAD:packages/swift-sdk/{path}", cwd=platform_dir)
    if run("git", "status", "--porcelain", "--untracked-files=all", "--", "packages/swift-sdk", cwd=platform_dir):
        raise ValueError("SwiftDashSDK has local changes; captured evidence must belong to the exact Platform commit")
    return sdk


def validate_inventory(schema, inventory):
    if inventory.get("format_version") != 1 or set(schema["entity_hashes"]) != set(inventory["models"]):
        raise ValueError("Captured entities differ from schema-models.json; update the source inventory before shipping")


def capture(platform_dir, output_dir):
    platform_dir, output_dir = pathlib.Path(platform_dir).resolve(), pathlib.Path(output_dir).resolve()
    sdk = validate_capture_checkout(platform_dir)
    subprocess.run(["python3", str(sdk / "scripts/freeze_schema_models.py"), "--check-inventory"], cwd=platform_dir, check=True)
    subprocess.run(["python3", str(sdk / "scripts/freeze_schema_models.py"), "--check"], cwd=platform_dir, check=True)
    if output_dir.exists():
        raise ValueError("Capture output directory already exists; do not overwrite release evidence")
    output_dir.mkdir(parents=True)
    devices = json.loads(run("xcrun", "simctl", "list", "devices", "available", "--json"))["devices"]
    runtime, device = select_simulator(devices)
    with tempfile.TemporaryDirectory(prefix="schema-capture-") as scratch:
        result = pathlib.Path(scratch) / "capture.xcresult"
        subprocess.run([
            "xcodebuild", "test", "-scheme", "SwiftDashSDK", "-configuration", "Release",
            "-destination", f"platform=iOS Simulator,id={device['udid']},arch=arm64",
            "-derivedDataPath", str(pathlib.Path(scratch) / "DerivedData"),
            "-resultBundlePath", str(result),
            "-only-testing:SwiftDashSDKTests/DashSchemaReleaseCaptureTests/testCaptureReleaseSchema",
            "-only-testing:SwiftDashSDKTests/DashModelMigrationTests",
            "-only-testing:SwiftDashSDKTests/DashReleasedSchemaTests",
            "-only-testing:SwiftDashSDKTests/DashLegacySchemaMigrationTests",
            "CODE_SIGNING_ALLOWED=NO", "ARCHS=arm64", "ENABLE_TESTABILITY=YES",
        ], cwd=sdk, check=True)
        exported = pathlib.Path(scratch) / "attachments"
        subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(result),
                        "--output-path", str(exported)], check=True)
        extract_attachments(exported, output_dir)
    schema = json.loads((output_dir / "schema.json").read_text())
    inventory = json.loads((sdk / "schema-models.json").read_text())
    validate_inventory(schema, inventory)
    (output_dir / "toolchain.json").write_text(json.dumps({
        "xcode": run("xcodebuild", "-version"), "simulator_runtime": runtime,
    }, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform-dir", required=True)
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()
    capture(args.platform_dir, args.output_dir)
