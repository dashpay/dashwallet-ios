"""No localization comment carries a BartyCrouch directive (`#bc-ignore!` and the like).

BartyCrouch is gone (the String Catalog replaced it), so a directive no longer controls anything and
shows translators a tool command instead of context. Checks the Catalog's comments and the comments
of the Swift lookups the build writes into it.

Run from the repository root:

    python3 -m unittest discover -s scripts/localization/tests -p 'test_*.py'
"""
import os
import re
import subprocess
import sys
import unittest

LOCALIZATION_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.dirname(os.path.dirname(LOCALIZATION_DIR))
sys.path.insert(0, LOCALIZATION_DIR)

import catalog_io  # noqa: E402

DIRECTIVE = re.compile(r"#bc-")


class NoBartyCrouchDirectiveTests(unittest.TestCase):
    def test_no_catalog_comment_holds_a_directive(self):
        strings = catalog_io.read_catalog(os.path.join(REPO, "DashWallet", "Localizable.xcstrings"))["strings"]
        found = sorted(k for k, e in strings.items() if DIRECTIVE.search(e.get("comment") or ""))
        self.assertEqual(found, [])

    def test_no_swift_lookup_comment_holds_a_directive(self):
        res = subprocess.run(["git", "-C", REPO, "grep", "-n", "-E", r'comment: *"#bc-', "--", "*.swift"],
                             capture_output=True, text=True)
        self.assertIn(res.returncode, (0, 1), "git grep could not run: %s" % res.stderr)  # 1 = no match
        self.assertEqual(res.stdout, "")


if __name__ == "__main__":
    unittest.main()
