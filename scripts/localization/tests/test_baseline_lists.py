"""The Baseline reader lives in baseline_lists, and no kept file depends on the removed migration tools.

Run from the repository root:

    python3 -m unittest discover -s scripts/localization/tests -p 'test_baseline_lists.py'

The Catalog generator, the codemod, the entry mover, the Catalog project helper and
regenerate.sh were removed once the migration was done. No file that stays imports or runs
them, and the Baseline reader is importable from baseline_lists.
"""
import ast
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
LOCALIZATION_DIR = os.path.dirname(HERE)
REPO_ROOT = os.path.dirname(os.path.dirname(LOCALIZATION_DIR))
FIXTURE_REPO = os.path.join(LOCALIZATION_DIR, "fixtures", "zero_loss", "repo")
sys.path.insert(0, LOCALIZATION_DIR)

# The removed migration tools (relative to scripts/localization).
REMOVED_FILES = {
    "generate_catalog.py", "move_entries.py", "catalog_project.py", "regenerate.sh",
    "tests/test_generate_catalog.py", "tests/test_move_entries.py", "tests/test_catalog_project.py",
}
REMOVED_DIRS = ("codemod", "fixtures/catalog", "fixtures/move")
REMOVED_MODULES = ("generate_catalog", "move_entries", "catalog_project")


def kept_files(extensions):
    for root, dirs, files in os.walk(LOCALIZATION_DIR):
        dirs[:] = [d for d in dirs if d != "__pycache__"]
        for name in files:
            path = os.path.join(root, name)
            rel = os.path.relpath(path, LOCALIZATION_DIR).replace(os.sep, "/")
            if rel in REMOVED_FILES or any(rel.startswith(d + "/") for d in REMOVED_DIRS):
                continue
            if name.endswith(extensions):
                yield rel, path


def imported_modules(path):
    with open(path, encoding="utf-8") as f:
        tree = ast.parse(f.read(), path)
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                yield alias.name.split(".")[0]
        elif isinstance(node, ast.ImportFrom) and node.module:
            yield node.module.split(".")[0]


def git(repo, *args):
    return subprocess.run(["git", "-C", repo] + list(args), check=True, capture_output=True,
                          text=True).stdout.strip()


class KeptFilesDoNotNeedRemovedToolsTests(unittest.TestCase):
    def test_no_kept_python_file_imports_a_removed_module(self):
        offenders = []
        for rel, path in kept_files((".py",)):
            for mod in imported_modules(path):
                if mod in REMOVED_MODULES:
                    offenders.append("%s imports %s" % (rel, mod))
        self.assertEqual(offenders, [])

    def test_no_kept_script_or_workflow_runs_a_removed_tool(self):
        pattern = re.compile(r"generate_catalog|move_entries|catalog_project|regenerate\.sh")
        offenders = []
        for rel, path in kept_files((".sh",)):
            with open(path, encoding="utf-8") as f:
                if pattern.search(f.read()):
                    offenders.append(rel)
        workflows = os.path.join(REPO_ROOT, ".github")
        for root, _, files in os.walk(workflows):
            for name in files:
                with open(os.path.join(root, name), encoding="utf-8", errors="replace") as f:
                    if pattern.search(f.read()):
                        offenders.append(os.path.relpath(os.path.join(root, name), REPO_ROOT))
        self.assertEqual(offenders, [])


class BaselineListsModuleTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="baseline-lists-")
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.repo = os.path.join(self.tmp, "repo")
        shutil.copytree(FIXTURE_REPO, self.repo)
        git(self.repo, "init", "-q")
        git(self.repo, "config", "user.email", "test@example.invalid")
        git(self.repo, "config", "user.name", "Test")
        git(self.repo, "config", "commit.gpgsign", "false")
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "-m", "baseline")
        self.rev = git(self.repo, "rev-parse", "HEAD")

    def test_exposes_the_reader_api(self):
        import baseline_lists
        self.assertEqual(baseline_lists.LISTS_DIR, "DashWallet")
        self.assertTrue(issubclass(baseline_lists.GenerateError, Exception))
        self.assertTrue(callable(baseline_lists.build_catalog))
        self.assertTrue(callable(baseline_lists.locale_files))

    def test_reads_the_baseline_lists(self):
        import baseline_lists
        self.assertEqual(sorted(baseline_lists.locale_files(self.repo, self.rev)), ["de", "en", "uk"])
        cat = baseline_lists.build_catalog(self.repo, self.rev)
        self.assertEqual(cat["sourceLanguage"], "en")
        self.assertTrue(cat["strings"])
        for entry in cat["strings"].values():
            self.assertTrue({"en", "de", "uk"} >= set(entry["localizations"]))

    def test_does_not_depend_on_the_generator(self):
        path = os.path.join(LOCALIZATION_DIR, "baseline_lists.py")
        self.assertTrue(os.path.exists(path), path)
        self.assertNotIn("generate_catalog", set(imported_modules(path)))


if __name__ == "__main__":
    unittest.main()
