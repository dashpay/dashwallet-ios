import json
import pathlib
import tempfile
import unittest
from unittest import mock

from capture_schema_release import capture, extract_attachments, select_simulator, validate_capture_checkout, validate_inventory


class CapturePreflightTest(unittest.TestCase):
    def test_all_required_test_classes_are_checked_before_starting_xcode(self):
        required = ["schema-models.json", "scripts/freeze_schema_models.py"] + [
            f"SwiftTests/SwiftDashSDKTests/{name}.swift" for name in (
                "DashSchemaReleaseCaptureTests", "DashModelMigrationTests", "DashReleasedSchemaTests",
                "DashLegacySchemaMigrationTests")
        ]
        with tempfile.TemporaryDirectory() as root:
            sdk = pathlib.Path(root) / "packages/swift-sdk"
            for path in required:
                file = sdk / path
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text("test")
            for path in required:
                with self.subTest(missing=path):
                    (sdk / path).unlink()
                    with mock.patch("capture_schema_release.run") as run:
                        with self.assertRaisesRegex(ValueError, path):
                            validate_capture_checkout(root)
                        run.assert_not_called()
                    (sdk / path).write_text("test")
            with mock.patch("capture_schema_release.run", return_value="") as run:
                self.assertEqual(validate_capture_checkout(root), sdk.resolve())
                self.assertEqual(run.call_count, len(required) + 1)

    def test_capture_requires_exact_live_inventory_membership(self):
        schema = {"entity_hashes": {"Wallet": "abcd", "Account": "dcba"}}
        inventory = {"format_version": 1, "models": {"Wallet": "wallet.swift", "Account": "account.swift"}}
        validate_inventory(schema, inventory)
        for names in ({"Wallet": "wallet.swift"}, dict(inventory["models"], Extra="extra.swift")):
            with self.assertRaisesRegex(ValueError, "update the source inventory before shipping"):
                validate_inventory(schema, dict(inventory, models=names))

    def test_capture_runs_legacy_migrations_before_recording_release_evidence(self):
        with tempfile.TemporaryDirectory() as root:
            root = pathlib.Path(root)
            sdk = root / "platform/packages/swift-sdk"
            sdk.mkdir(parents=True)
            (sdk / "schema-models.json").write_text(json.dumps({
                "format_version": 1, "models": {"Wallet": "wallet.swift"},
            }))
            devices = {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
                {"isAvailable": True, "name": "iPhone 17", "udid": "simulator"},
            ]}}

            def extract(_source, output):
                (output / "schema.json").write_text(json.dumps({"entity_hashes": {"Wallet": "abcd"}}))
                (output / "fixture.store").write_bytes(b"synthetic fixture")

            with mock.patch("capture_schema_release.validate_capture_checkout", return_value=sdk), \
                    mock.patch("capture_schema_release.run", side_effect=[json.dumps(devices), "Xcode test"]), \
                    mock.patch("capture_schema_release.extract_attachments", side_effect=extract), \
                    mock.patch("capture_schema_release.subprocess.run") as execute:
                capture(root / "platform", root / "evidence")

            builds = [call for call in execute.call_args_list if call.args[0][0] == "xcodebuild"]
            self.assertEqual(len(builds), 1)
            self.assertIn("-only-testing:SwiftDashSDKTests/DashLegacySchemaMigrationTests", builds[0].args[0])
            self.assertTrue(builds[0].kwargs["check"])


class SimulatorSelectionTest(unittest.TestCase):
    def test_selects_numeric_runtime_version_instead_of_lexicographic_order(self):
        devices = {
            "com.apple.CoreSimulator.SimRuntime.iOS-" + version: [
                {"isAvailable": True, "name": "iPhone 17", "udid": version}
            ]
            for version in ("9-3", "26", "26-5", "26-10", "26-10-1")
        }
        self.assertEqual(select_simulator(devices)[1]["udid"], "26-10-1")
        devices.pop("com.apple.CoreSimulator.SimRuntime.iOS-26-10-1")
        self.assertEqual(select_simulator(devices)[1]["udid"], "26-10")

    def test_duplicate_device_names_have_stable_selection(self):
        first = {"isAvailable": True, "name": "iPhone 17", "udid": "A"}
        second = dict(first, udid="B")
        runtime = "com.apple.CoreSimulator.SimRuntime.iOS-26-5"
        self.assertEqual(select_simulator({runtime: [first, second]}), (runtime, second))
        self.assertEqual(select_simulator({runtime: [second, first]}), (runtime, second))

    def test_unavailable_non_iphone_and_unrecognized_runtimes_are_excluded(self):
        phone = {"isAvailable": True, "name": "iPhone 17", "udid": "phone"}
        devices = {
            "com.apple.CoreSimulator.SimRuntime.tvOS-27": [phone],
            "com.apple.CoreSimulator.SimRuntime.iOS-27-beta": [phone],
            "com.apple.CoreSimulator.SimRuntime.iOS-27": [
                dict(phone, isAvailable=False), dict(phone, name="iPad Pro")
            ],
        }
        with self.assertRaisesRegex(ValueError, "No available iPhone"):
            select_simulator(devices)


class CaptureAttachmentsTest(unittest.TestCase):
    def test_extracts_only_the_named_capture_test_attachments(self):
        with tempfile.TemporaryDirectory() as root:
            source = pathlib.Path(root) / "source"
            target = pathlib.Path(root) / "target"
            source.mkdir()
            target.mkdir()
            attachments = []
            for name in ("schema.json", "fixture.store"):
                exported = "opaque-" + name
                (source / exported).write_bytes(name.encode())
                stem, extension = name.split(".")
                suggested = f"{stem}_0_CD00442A-8344-4DFD-AF1B-AF3D37AF0E4D.{extension}"
                attachments.append({"suggestedHumanReadableName": suggested, "exportedFileName": exported})
            manifest = [{"testIdentifier": "DashSchemaReleaseCaptureTests/testCaptureReleaseSchema()", "attachments": attachments}]
            manifest.append({"testIdentifier": "UnrelatedTests/testOther()", "attachments": attachments})
            (source / "manifest.json").write_text(json.dumps(manifest))
            extract_attachments(source, target)
            self.assertEqual((target / "fixture.store").read_bytes(), b"fixture.store")
            self.assertEqual((target / "schema.json").read_bytes(), b"schema.json")
            manifest[0]["attachments"].append(attachments[0])
            (source / "manifest.json").write_text(json.dumps(manifest))
            with self.assertRaises(ValueError):
                extract_attachments(source, target)

    def test_missing_capture_is_not_silently_accepted(self):
        with tempfile.TemporaryDirectory() as root:
            path = pathlib.Path(root)
            (path / "manifest.json").write_text("[]")
            with self.assertRaises(ValueError):
                extract_attachments(path, path)


if __name__ == "__main__":
    unittest.main()
