"""The localization tools and the build's sync phase cite this feature's ADRs by their log numbers.

The feature drafted its decisions under its own numbers and promoted them into `docs/adr/`, where
the same numbers mean other decisions; after promotion the log copy is the record. A cited number
must name a log record that links back to this feature.

Run from the repository root:

    python3 -m unittest discover -s scripts/localization/tests -p 'test_*.py'
"""
import os
import re
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
LOCALIZATION_DIR = os.path.dirname(HERE)
REPO = os.path.abspath(os.path.join(LOCALIZATION_DIR, "..", ".."))
ADR_DIR = os.path.join(REPO, "docs", "adr")
PROJECT = os.path.join(REPO, "DashWallet.xcodeproj", "project.pbxproj")
FEATURE_LINK = "features/string-catalogs-migration/"
CITATION = re.compile(r"\bADR-(\d{4})\b")


def feature_records():
    numbers = set()
    for name in os.listdir(ADR_DIR):
        match = re.match(r"(\d{4})-", name)
        if match:
            with open(os.path.join(ADR_DIR, name), encoding="utf-8") as f:
                if FEATURE_LINK in f.read():
                    numbers.add(match.group(1))
    return numbers


def sync_phase_scripts(project_text):
    return [s for s in re.findall(r'shellScript = "((?:[^"\\]|\\.)*)";', project_text)
            if "sync_catalog.py" in s]


def citing_texts():
    """(where, text) for every kept file under scripts/localization and the sync phase's script."""
    for root, dirs, files in os.walk(LOCALIZATION_DIR):
        dirs[:] = [d for d in dirs if d not in ("fixtures", "__pycache__", ".build")]
        for name in files:
            if name.endswith((".py", ".sh", ".swift", ".md")):
                path = os.path.join(root, name)
                with open(path, encoding="utf-8") as f:
                    yield os.path.relpath(path, REPO), f.read()
    with open(PROJECT, encoding="utf-8") as f:
        for script in sync_phase_scripts(f.read()):
            yield "the Sync String Catalog phase", script


class AdrCitationTests(unittest.TestCase):
    def test_every_cited_adr_is_a_record_of_this_feature(self):
        allowed = feature_records()
        self.assertTrue(allowed, "no ADR in docs/adr links to " + FEATURE_LINK)
        wrong = sorted("%s: ADR-%s" % (where, number)
                       for where, text in citing_texts()
                       for number in set(CITATION.findall(text)) - allowed)
        self.assertEqual(wrong, [], "cites an ADR number that is not one of this feature's log records")

    def test_the_sync_phase_is_found_and_cites_its_records(self):
        with open(PROJECT, encoding="utf-8") as f:
            scripts = sync_phase_scripts(f.read())
        self.assertEqual(len(scripts), 1)
        self.assertTrue(CITATION.search(scripts[0]), scripts[0])


if __name__ == "__main__":
    unittest.main()
