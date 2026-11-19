"""Tests for catalog_project.py: the project file references the Catalog instead of the 86 lists."""
import os
import subprocess
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))

import catalog_project  # noqa: E402

BASELINE_REV = "e798ee8f2"


def baseline_project():
    return subprocess.check_output(
        ["git", "-C", REPO, "show", BASELINE_REV + ":DashWallet.xcodeproj/project.pbxproj"]).decode("utf-8")


class CatalogProjectTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.before = baseline_project()
        cls.after = catalog_project.reference_catalog(cls.before)

    def test_no_list_is_referenced(self):
        self.assertNotIn("Localizable.strings", self.after.replace("Localizable.stringsdata", ""))
        self.assertNotIn("Localizable.stringsdict", self.after)

    def test_catalog_is_a_file_reference_in_its_section(self):
        refs = self.after.split("/* Begin PBXFileReference section */")[1].split("/* End PBXFileReference section */")[0]
        self.assertIn(catalog_project.STRINGS_GROUP + " /* Localizable.xcstrings */ = {isa = PBXFileReference; "
                      "lastKnownFileType = text.json.xcstrings; path = Localizable.xcstrings; "
                      'sourceTree = "<group>"; };', refs)

    def test_every_target_that_had_the_strings_gets_the_catalog(self):
        self.assertEqual(self.after.count("/* Localizable.xcstrings in Resources */"),
                         self.before.count("/* Localizable.strings in Resources */"))

    def test_rest_of_the_file_is_untouched(self):
        removed = [l for l in self.before.splitlines() if l not in set(self.after.splitlines())]
        for line in removed:
            self.assertRegex(line, r"Localizable|\.lproj|PBXVariantGroup|^\t\t\t\);$|^\t\t\};$|children = \(|name = |sourceTree|isa = |^\t\t\t\t[0-9A-F]{24} /\* [\w-]+ \*/,$",
                             line)

    def test_running_twice_changes_nothing(self):
        self.assertEqual(catalog_project.reference_catalog(self.after), self.after)


if __name__ == "__main__":
    unittest.main()
