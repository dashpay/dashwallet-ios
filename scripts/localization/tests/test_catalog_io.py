"""Tests for catalog_io.publish_file / publish_text: the one way a tool puts a file into the checkout
(the Catalog by the sync phase, the key map, the plural-fidelity fixture).

Run from the repository root:

    python3 -m unittest discover -s scripts/localization/tests -p 'test_*.py'

Contract: publish_file(path, staged, want, watched) puts the finished file `staged` at `path` only over
the bytes `want` (None: `path` must not exist) and only while every file in `watched` still holds the
bytes the caller read. It never replaces bytes it did not verify: a save that lands at any moment of
the publication stays (at `path`, or in a conflict file the error names) and CatalogIOError is raised.
publish_text(path, text, expect) stages `text` and publishes it with want=expect[path].
No staging or moved-aside file is left behind.
"""
import ast
import json
import os
import shutil
import sys
import tempfile
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

import catalog_io  # noqa: E402


class PublishTextTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="catalog-io-test-")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.source = os.path.join(self.tmp, "Localizable.xcstrings")
        self.out = os.path.join(self.tmp, "map.json")
        for path, text in ((self.source, b"source v1"), (self.out, b"old map")):
            with open(path, "wb") as f:
                f.write(text)

    def read(self, path):
        with open(path, "rb") as f:
            return f.read()

    def test_writes_while_every_read_file_is_unchanged(self):
        catalog_io.publish_text(self.out, "new map\n", {self.source: b"source v1", self.out: b"old map"})
        self.assertEqual(self.read(self.out), b"new map\n")
        self.assertEqual(sorted(os.listdir(self.tmp)), ["Localizable.xcstrings", "map.json"])

    def test_a_source_saved_after_it_was_read_refuses_the_write(self):
        with open(self.source, "wb") as f:
            f.write(b"source v2")
        with self.assertRaises(catalog_io.CatalogIOError) as cm:
            catalog_io.publish_text(self.out, "new map\n", {self.source: b"source v1", self.out: b"old map"})
        self.assertIn(self.source, str(cm.exception))
        self.assertEqual(self.read(self.out), b"old map")
        self.assertEqual(sorted(os.listdir(self.tmp)), ["Localizable.xcstrings", "map.json"])

    def test_an_edit_of_the_target_itself_is_not_overwritten(self):
        with open(self.out, "wb") as f:
            f.write(b"hand-edited map")
        with self.assertRaises(catalog_io.CatalogIOError):
            catalog_io.publish_text(self.out, "new map\n", {self.out: b"old map"})
        self.assertEqual(self.read(self.out), b"hand-edited map")

    def test_a_file_that_appeared_after_it_was_read_as_absent_refuses_the_write(self):
        fresh = os.path.join(self.tmp, "fresh.json")
        with open(fresh, "wb") as f:
            f.write(b"someone else's")
        with self.assertRaises(catalog_io.CatalogIOError):
            catalog_io.publish_text(fresh, "mine\n", {fresh: None})
        self.assertEqual(self.read(fresh), b"someone else's")

    def test_read_bytes_is_none_for_a_missing_file(self):
        self.assertIsNone(catalog_io.read_bytes(os.path.join(self.tmp, "missing")))
        self.assertEqual(catalog_io.read_bytes(self.source), b"source v1")


class PublishWindowTest(unittest.TestCase):
    """UU1: a save landing inside the publication itself is never replaced."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="catalog-io-window-")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.path = os.path.join(self.tmp, "Localizable.xcstrings")
        with open(self.path, "wb") as f:
            f.write(b"as read")
        os.chmod(self.path, 0o640)

    def read(self, path):
        with open(path, "rb") as f:
            return f.read()

    def others(self):
        return sorted(n for n in os.listdir(self.tmp) if n != "Localizable.xcstrings")

    def test_publishes_over_the_verified_bytes_and_keeps_the_mode(self):
        catalog_io.publish_text(self.path, "result", {self.path: b"as read"})
        self.assertEqual(self.read(self.path), b"result")
        self.assertEqual(os.stat(self.path).st_mode & 0o777, 0o640)
        self.assertEqual(self.others(), [])

    def test_an_editor_save_between_the_move_and_the_link_stays(self):
        # An atomic save (what Xcode does) creates a new file at the path while it is moved aside.
        real_rename = os.rename

        def rename_then_save(src, dst):
            real_rename(src, dst)
            if src == self.path:
                with open(self.path, "wb") as f:
                    f.write(b"saved in the window")
        with mock.patch.object(catalog_io.os, "rename", rename_then_save):
            with self.assertRaises(catalog_io.CatalogIOError) as cm:
                catalog_io.publish_text(self.path, "result", {self.path: b"as read"})
        self.assertIn(self.path, str(cm.exception))
        self.assertEqual(self.read(self.path), b"saved in the window")
        self.assertEqual(self.others(), [])

    def test_a_write_into_the_moved_aside_file_is_kept_as_a_conflict_file(self):
        # A writer holding the file open writes into the moved-aside file after it was verified.
        handle = open(self.path, "r+b")
        self.addCleanup(handle.close)
        real_link = os.link

        def write_then_link(src, dst, **kw):
            if dst == self.path:
                handle.seek(0)
                handle.write(b"written in the window")
                handle.flush()
            return real_link(src, dst, **kw)
        with mock.patch.object(catalog_io.os, "link", write_then_link):
            with self.assertRaises(catalog_io.CatalogIOError) as cm:
                catalog_io.publish_text(self.path, "result", {self.path: b"as read"})
        conflicts = [n for n in self.others() if ".conflict-" in n]
        self.assertEqual(len(conflicts), 1, self.others())
        self.assertIn(conflicts[0], str(cm.exception))
        self.assertEqual(self.read(os.path.join(self.tmp, conflicts[0])), b"written in the window")
        self.assertEqual(self.others(), conflicts)

    def test_a_save_between_the_check_and_the_move_stays(self):
        # The live file is verified only after it was moved aside, so no check-to-replace window remains.
        real_rename = os.rename

        def save_then_rename(src, dst):
            if src == self.path:
                with open(self.path, "wb") as f:
                    f.write(b"saved just before the move")
            real_rename(src, dst)
        with mock.patch.object(catalog_io.os, "rename", save_then_rename):
            with self.assertRaises(catalog_io.CatalogIOError):
                catalog_io.publish_text(self.path, "result", {self.path: b"as read"})
        self.assertEqual(self.read(self.path), b"saved just before the move")
        self.assertEqual(self.others(), [])

    def test_a_file_created_while_an_absent_target_is_published_stays(self):
        fresh = os.path.join(self.tmp, "fresh.json")
        real_link = os.link

        def create_then_link(src, dst, **kw):
            if dst == fresh:
                with open(fresh, "wb") as f:
                    f.write(b"someone else's")
            return real_link(src, dst, **kw)
        with mock.patch.object(catalog_io.os, "link", create_then_link):
            with self.assertRaises(catalog_io.CatalogIOError):
                catalog_io.publish_text(fresh, "mine", {fresh: None})
        self.assertEqual(self.read(fresh), b"someone else's")

    def assert_back_and_clean(self):
        self.assertEqual(self.read(self.path), b"as read")
        self.assertEqual(os.stat(self.path).st_mode & 0o777, 0o640)
        self.assertEqual(self.others(), [])

    def test_a_failing_link_puts_the_file_back(self):
        # VV1: a filesystem error after the move must not leave the path missing
        real_link = os.link

        def failing_link(src, dst, **kw):
            if dst == self.path and not src.endswith(".aside"):
                raise PermissionError(1, "Operation not permitted")
            return real_link(src, dst, **kw)
        with mock.patch.object(catalog_io.os, "link", failing_link):
            with self.assertRaises(PermissionError):
                catalog_io.publish_text(self.path, "result", {self.path: b"as read"})
        self.assert_back_and_clean()

    def test_an_interrupt_during_the_check_puts_the_file_back(self):
        real_read = catalog_io.read_bytes

        def interrupted(path):
            if path.endswith(".aside"):
                raise KeyboardInterrupt
            return real_read(path)
        with mock.patch.object(catalog_io, "read_bytes", interrupted):
            with self.assertRaises(KeyboardInterrupt):
                catalog_io.publish_text(self.path, "result", {self.path: b"as read"})
        self.assert_back_and_clean()

    def test_an_interrupt_right_after_the_move_puts_the_file_back(self):
        # WW1: the rename finished, then Ctrl-C arrived before the next statement
        real_rename = os.rename

        def rename_then_interrupt(src, dst):
            real_rename(src, dst)
            if src == self.path:
                raise KeyboardInterrupt
        with mock.patch.object(catalog_io.os, "rename", rename_then_interrupt):
            with self.assertRaises(KeyboardInterrupt):
                catalog_io.publish_text(self.path, "result", {self.path: b"as read"})
        self.assert_back_and_clean()

    def test_a_filesystem_without_hard_links_refuses_before_the_move(self):
        # WW2: every link fails (exFAT, some network shares); the file must never be moved
        with mock.patch.object(catalog_io.os, "link", side_effect=OSError(45, "Operation not supported")), \
                mock.patch.object(catalog_io.os, "rename", side_effect=AssertionError("moved")):
            with self.assertRaises(catalog_io.CatalogIOError) as cm:
                catalog_io.publish_text(self.path, "result", {self.path: b"as read"})
        self.assertIn("hard link", str(cm.exception))
        self.assert_back_and_clean()

    def test_a_put_back_that_cannot_link_names_the_moved_aside_file(self):
        real_link = os.link

        def links_fail_after_the_probe(src, dst, **kw):
            if dst == self.path:
                raise OSError(5, "Input/output error")
            return real_link(src, dst, **kw)
        with mock.patch.object(catalog_io.os, "link", links_fail_after_the_probe):
            with self.assertRaises(catalog_io.CatalogIOError) as cm:
                catalog_io.publish_text(self.path, "result", {self.path: b"as read"})
        aside = [n for n in self.others() if n.endswith(".aside")]
        self.assertEqual(len(aside), 1, self.others())
        self.assertIn(os.path.join(self.tmp, aside[0]), str(cm.exception))
        self.assertEqual(self.read(os.path.join(self.tmp, aside[0])), b"as read")

    def test_an_interrupt_sent_while_the_file_is_moved_aside_waits_for_the_publication(self):
        # XX1: a signal at any point between the move and the link is delivered only after the link
        import signal
        real_read = catalog_io.read_bytes

        def read_and_interrupt(path):
            if path.endswith(".aside"):
                os.kill(os.getpid(), signal.SIGINT)
            return real_read(path)
        with mock.patch.object(catalog_io, "read_bytes", read_and_interrupt):
            with self.assertRaises(KeyboardInterrupt):
                catalog_io.publish_text(self.path, "result", {self.path: b"as read"})
        self.assertEqual(self.read(self.path), b"result")
        self.assertEqual(self.others(), [])

    def test_a_signal_sent_at_the_callee_s_entry_waits_too(self):
        import signal
        real = catalog_io._move_aside_and_link

        def interrupted_at_entry(*args):
            os.kill(os.getpid(), signal.SIGINT)
            return real(*args)
        with mock.patch.object(catalog_io, "_move_aside_and_link", interrupted_at_entry):
            with self.assertRaises(KeyboardInterrupt):
                catalog_io.publish_text(self.path, "result", {self.path: b"as read"})
        self.assertEqual(self.read(self.path), b"result")
        self.assertEqual(self.others(), [])

    def test_a_conflict_file_that_cannot_be_renamed_names_the_moved_aside_file(self):
        handle = open(self.path, "r+b")
        self.addCleanup(handle.close)
        real_link, real_rename = os.link, os.rename

        def write_then_link(src, dst, **kw):
            if dst == self.path:
                handle.seek(0)
                handle.write(b"written in the window")
                handle.flush()
            return real_link(src, dst, **kw)

        def no_conflict_rename(src, dst):
            if ".conflict-" in dst:
                raise OSError(5, "Input/output error")
            return real_rename(src, dst)
        with mock.patch.object(catalog_io.os, "link", write_then_link), \
                mock.patch.object(catalog_io.os, "rename", no_conflict_rename):
            with self.assertRaises(catalog_io.CatalogIOError) as cm:
                catalog_io.publish_text(self.path, "result", {self.path: b"as read"})
        aside = [n for n in self.others() if n.endswith(".aside")]
        self.assertEqual(len(aside), 1, self.others())
        self.assertIn(os.path.join(self.tmp, aside[0]), str(cm.exception))
        self.assertEqual(self.read(os.path.join(self.tmp, aside[0])), b"written in the window")

    def test_an_empty_leftover_moved_aside_file_refuses_too(self):
        # It may be another run's, about to receive the old file; never remove it.
        leftover = os.path.join(self.tmp, ".Localizable.xcstrings.abc123.aside")
        with open(leftover, "wb"):
            pass
        with self.assertRaises(catalog_io.CatalogIOError) as cm:
            catalog_io.publish_text(self.path, "result", {self.path: b"as read"})
        self.assertIn(leftover, str(cm.exception))
        self.assertTrue(os.path.exists(leftover))
        self.assertEqual(self.read(self.path), b"as read")

    def test_an_interrupt_while_the_hold_starts_restores_the_mask(self):
        import signal
        before = signal.pthread_sigmask(signal.SIG_BLOCK, [])
        real = signal.pthread_sigmask
        calls = []

        def interrupted(how, mask):
            calls.append(how)
            result = real(how, mask)
            if how == signal.SIG_BLOCK and mask:
                raise KeyboardInterrupt
            return result
        with mock.patch.object(catalog_io.signal, "pthread_sigmask", interrupted):
            with self.assertRaises(KeyboardInterrupt):
                catalog_io.publish_text(self.path, "result", {self.path: b"as read"})
        self.assertEqual(signal.pthread_sigmask(signal.SIG_BLOCK, []), before)
        self.assert_back_and_clean()

    def test_a_leftover_moved_aside_file_refuses_and_is_named(self):
        # Bytes of an interrupted publication may be in it; nobody may publish past them.
        leftover = os.path.join(self.tmp, ".Localizable.xcstrings.abc123.aside")
        with open(leftover, "wb") as f:
            f.write(b"only copy")
        with self.assertRaises(catalog_io.CatalogIOError) as cm:
            catalog_io.publish_text(self.path, "result", {self.path: b"as read"})
        self.assertIn(leftover, str(cm.exception))
        self.assertEqual(self.read(self.path), b"as read")
        self.assertEqual(self.read(leftover), b"only copy")

    def test_a_changed_live_file_is_never_moved(self):
        # VV6: a mismatch found before the move leaves the path in place the whole time
        with open(self.path, "wb") as f:
            f.write(b"saved before")
        with mock.patch.object(catalog_io.os, "rename", side_effect=AssertionError("moved")):
            with self.assertRaises(catalog_io.CatalogIOError):
                catalog_io.publish_text(self.path, "result", {self.path: b"as read"})
        self.assertEqual(self.read(self.path), b"saved before")

    def test_a_path_removed_before_publication_is_the_tool_s_own_error(self):
        os.remove(self.path)
        with self.assertRaises(catalog_io.CatalogIOError):
            catalog_io.publish_text(self.path, "result", {self.path: b"as read"})
        self.assertEqual(self.others(), [])

    def test_a_write_into_the_aside_file_survives_an_editor_save_in_the_same_window(self):
        # VV3: both land between the move and the link; neither may be dropped
        handle = open(self.path, "r+b")
        self.addCleanup(handle.close)
        real_link = os.link

        def both_then_link(src, dst, **kw):
            if dst == self.path and not src.endswith(".aside"):
                handle.seek(0)
                handle.write(b"written in the window")
                handle.flush()
                with open(self.path, "wb") as f:
                    f.write(b"saved in the window")
            return real_link(src, dst, **kw)
        with mock.patch.object(catalog_io.os, "link", both_then_link):
            with self.assertRaises(catalog_io.CatalogIOError) as cm:
                catalog_io.publish_text(self.path, "result", {self.path: b"as read"})
        self.assertEqual(self.read(self.path), b"saved in the window")
        conflicts = [n for n in self.others() if ".conflict-" in n]
        self.assertEqual(len(conflicts), 1, self.others())
        self.assertIn(conflicts[0], str(cm.exception))
        self.assertEqual(self.read(os.path.join(self.tmp, conflicts[0])), b"written in the window")

    def test_the_target_must_be_among_the_verified_files(self):
        with self.assertRaises(KeyError):
            catalog_io.publish_text(self.path, "result", {})
        self.assertEqual(self.read(self.path), b"as read")


class WritersGoThroughPublishTextTest(unittest.TestCase):
    """The key map and the plural-fidelity fixture refuse to replace what changed since it was read."""

    def setUp(self):
        import zero_loss_check
        self.zl = zero_loss_check
        self.repo = tempfile.mkdtemp(prefix="catalog-io-repo-")
        self.addCleanup(shutil.rmtree, self.repo, True)
        self.catalog = os.path.join(self.repo, zero_loss_check.CATALOG)
        self.key_map = os.path.join(self.repo, zero_loss_check.KEY_MAP)
        for path, text in ((self.catalog, b'{"strings": {}}'), (self.key_map, b'{"old": 1}\n')):
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as f:
                f.write(text)
        self.read_before = {self.catalog: b'{"strings": {}}', self.key_map: b'{"old": 1}\n'}

    def test_the_key_map_is_not_written_over_a_catalog_saved_after_the_run_read_it(self):
        with open(self.catalog, "wb") as f:
            f.write(b'{"strings": {"saved later": {}}}')
        with self.assertRaises(catalog_io.CatalogIOError):
            self.zl.write_key_map(self.repo, "0" * 40, {"a": ["a"]}, self.read_before)
        with open(self.key_map, "rb") as f:
            self.assertEqual(f.read(), b'{"old": 1}\n')

    def test_the_key_map_is_written_when_nothing_changed(self):
        self.zl.write_key_map(self.repo, "0" * 40, {"a": ["a"]}, self.read_before)
        with open(self.key_map, encoding="utf-8") as f:
            self.assertEqual(json.load(f), {"baseline": "0" * 40, "keys": {"a": ["a"]}})

    def test_the_fixture_is_not_written_from_a_key_map_changed_after_it_was_read(self):
        import baseline_plural_forms
        with open(self.key_map, "wb") as f:
            f.write(b'{"new": 2}\n')
        with self.assertRaises(catalog_io.CatalogIOError):
            baseline_plural_forms.write_fixture(self.repo, {"counts": []}, b'{"old": 1}\n', None)
        self.assertFalse(os.path.exists(os.path.join(self.repo, baseline_plural_forms.OUT)))

    def test_the_fixture_is_not_written_over_a_fixture_saved_after_it_was_read(self):
        import baseline_plural_forms
        fixture = os.path.join(self.repo, baseline_plural_forms.OUT)
        os.makedirs(os.path.dirname(fixture), exist_ok=True)
        with open(fixture, "wb") as f:
            f.write(b"saved later")
        with self.assertRaises(catalog_io.CatalogIOError):
            baseline_plural_forms.write_fixture(self.repo, {"counts": []}, b'{"old": 1}\n', b"as read")
        with open(fixture, "rb") as f:
            self.assertEqual(f.read(), b"saved later")

    def test_the_fixture_writer_names_a_moved_aside_fixture_before_any_work(self):
        import baseline_plural_forms
        fixture = os.path.join(self.repo, baseline_plural_forms.OUT)
        os.makedirs(os.path.dirname(fixture), exist_ok=True)
        aside = os.path.join(os.path.dirname(fixture), "." + os.path.basename(fixture) + ".abc123.aside")
        with open(aside, "wb") as f:
            f.write(b"only copy")
        with mock.patch.object(self.zl, "repo_root", return_value=self.repo), \
                mock.patch.object(self.zl, "load_key_map", return_value=("0" * 40, {}, b"{}")), \
                mock.patch.object(baseline_plural_forms, "compiled_locales",
                                  side_effect=AssertionError("worked past the leftover")):
            with self.assertRaises(self.zl.CannotRun) as cm:
                baseline_plural_forms.main()
        self.assertIn(aside, str(cm.exception))

    def test_refuse_leftover_names_only_the_path_s_own_moved_aside_files(self):
        other = os.path.join(os.path.dirname(self.catalog), ".Other.xcstrings.abc123.aside")
        with open(other, "wb"):
            pass
        catalog_io.refuse_leftover(self.catalog)
        own = os.path.join(os.path.dirname(self.catalog), ".Localizable.xcstrings.abc123.aside")
        with open(own, "wb"):
            pass
        with self.assertRaises(catalog_io.CatalogIOError) as cm:
            catalog_io.refuse_leftover(self.catalog)
        self.assertIn(own, str(cm.exception))

    def while_a_publication_holds_the_lock(self, path, call):
        """Run `call` in a thread while this test, as another process publishing `path`, holds its folder
        lock with the file moved aside. Once `call` reaches that lock (no timing guess), put the file back,
        release the lock and return what `call` returned."""
        import fcntl
        import threading
        folder = os.path.dirname(path)
        lock = os.open(folder, os.O_RDONLY)
        fcntl.flock(lock, fcntl.LOCK_EX)
        aside = os.path.join(folder, "." + os.path.basename(path) + ".abc123.aside")
        os.rename(path, aside)
        folder_ino = os.stat(folder).st_ino
        reached = threading.Event()
        real_flock = fcntl.flock

        def flock(fd, operation):
            if os.fstat(fd).st_ino == folder_ino:
                reached.set()
            return real_flock(fd, operation)
        outcome = {}

        def run():
            try:
                outcome["value"] = call()
            except BaseException as e:  # reported below, on the test's thread
                outcome["error"] = e
        caller = threading.Thread(target=run)
        try:
            with mock.patch.object(catalog_io.fcntl, "flock", flock):
                caller.start()
                reached_lock = reached.wait(10)
                os.rename(aside, path)
                os.close(lock)
                caller.join(10)
        finally:
            if os.path.exists(aside):
                os.rename(aside, path)
        self.assertTrue(reached_lock, "the caller never took the folder lock: %r" % outcome)
        self.assertNotIn("error", outcome)
        return outcome.get("value")

    def test_read_published_waits_for_a_publication_in_progress(self):
        got = self.while_a_publication_holds_the_lock(self.catalog,
                                                      lambda: catalog_io.read_published(self.catalog))
        self.assertEqual(got, b'{"strings": {}}')

    def test_the_key_map_is_published_after_a_catalog_publication_in_progress_ends(self):
        # publish_text holds the lock of each folder it watches: the Catalog, missing for a moment while
        # another process publishes it, is compared once that publication is done.
        self.while_a_publication_holds_the_lock(
            self.catalog, lambda: self.zl.write_key_map(self.repo, "0" * 40, {"a": ["a"]}, self.read_before))
        with open(self.key_map, encoding="utf-8") as f:
            self.assertEqual(json.load(f)["keys"], {"a": ["a"]})

    def test_the_tools_read_published_files_only_through_read_published(self):
        # One choke point for "is it missing": read under the publishers' lock (catalog_io.read_published).
        for name in ("zero_loss_check.py", "baseline_plural_forms.py"):
            with open(os.path.join(os.path.dirname(HERE), name), encoding="utf-8") as f:
                tree = ast.parse(f.read())
            called = {n.func.attr for n in ast.walk(tree)
                      if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
                      and isinstance(n.func.value, ast.Name) and n.func.value.id == "catalog_io"}
            with self.subTest(name=name):
                self.assertEqual(called & {"read_bytes", "read_catalog", "refuse_leftover"}, set())
            source = ast.unparse(tree)
            with self.subTest(name=name, what="no live Catalog compile"):
                self.assertNotIn("compile_catalog(os.path.join(repo, CATALOG)", source)

    def test_every_writer_publishes_through_publish_file(self):
        # One choke point: no tool writes a checkout file by os.replace or an open() for writing.
        import re
        for name in ("sync_catalog.py", "zero_loss_check.py", "baseline_plural_forms.py"):
            with open(os.path.join(os.path.dirname(HERE), name), encoding="utf-8") as f:
                source = f.read()
            self.assertIsNone(re.search(r"os\.replace\(", source), name)
        with open(os.path.join(os.path.dirname(HERE), "sync_catalog.py"), encoding="utf-8") as f:
            self.assertIn("catalog_io.publish_file(", f.read())
        self.assertTrue(re.search(r"def publish_text\(.*\n(.*\n)*?.*publish_file\(",
                                  open(os.path.join(os.path.dirname(HERE), "catalog_io.py"), encoding="utf-8").read()))


if __name__ == "__main__":
    unittest.main()
