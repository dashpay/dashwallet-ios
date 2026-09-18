import json
import pathlib
import tempfile
import unittest

from capture_schema_release import extract_attachments


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
