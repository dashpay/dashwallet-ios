"""The Swift helpers compile for the macOS host whatever SDK the caller's environment names.

The build's "Sync String Catalog" phase runs inside an iOS target, where Xcode exports `SDKROOT`
as the iPhoneSimulator SDK. A helper compiled there must still be a macOS executable.

Run from the repository root:

    python3 -m unittest discover -s scripts/localization/tests -p 'test_*.py'
"""
import os
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

import catalog_io  # noqa: E402
import foundation_format  # noqa: E402


def ios_sdk():
    return subprocess.run(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"],
                          capture_output=True, text=True, check=True).stdout.strip()


class HostCompileTests(unittest.TestCase):
    def assert_compiles_under_ios_environment(self, cache_variable, build):
        with tempfile.TemporaryDirectory() as cache:
            environment = {cache_variable: cache, "SDKROOT": ios_sdk(),
                           "PLATFORM_NAME": "iphonesimulator", "IPHONEOS_DEPLOYMENT_TARGET": "18.0"}
            with mock.patch.dict(os.environ, environment):
                binary = build()
            self.assertTrue(os.access(binary, os.X_OK), binary)
            self.assertTrue(binary.startswith(cache), binary)

    def test_the_catalog_writer_compiles_inside_an_ios_build_phase(self):
        self.assert_compiles_under_ios_environment("CATALOG_WRITER_CACHE", catalog_io._writer_binary)

    def test_the_formatter_compiles_inside_an_ios_build_phase(self):
        self.assert_compiles_under_ios_environment("FORMATTER_CACHE", foundation_format._binary)


if __name__ == "__main__":
    unittest.main()
