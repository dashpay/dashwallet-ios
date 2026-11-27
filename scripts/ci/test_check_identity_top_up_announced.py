#!/usr/bin/env python3
"""Tests for check_identity_top_up_announced.py."""
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "check_identity_top_up_announced.py")
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class IdentityTopUpAnnouncedGuardTest(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="top-up-guard-")
        self.addCleanup(shutil.rmtree, self.root, True)

    def write(self, rel, text):
        path = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)

    def run_guard(self, root=None):
        return subprocess.run([sys.executable, SCRIPT, "--root", root or self.root],
                              capture_output=True, text=True, timeout=60)

    def test_every_method_outside_announcing_fails_and_is_named(self):
        self.write("DashWallet/Sources/A.swift",
                   "func a() async throws {\n"
                   "    _ = try await wallet.topUpIdentityWithFunding(identityId: id)\n"
                   "    _ = try await wallet.topUpIdentityFromAddresses(identityId: id)\n"
                   "    _ = try await wallet.resumeTopUpWithAssetLock(identityId: id)\n"
                   "}\n")
        res = self.run_guard()
        self.assertEqual(res.returncode, 1)
        self.assertIn("DashWallet/Sources/A.swift:2: topUpIdentityWithFunding outside", res.stdout)
        self.assertIn("DashWallet/Sources/A.swift:3: topUpIdentityFromAddresses outside", res.stdout)
        self.assertIn("DashWallet/Sources/A.swift:4: resumeTopUpWithAssetLock outside", res.stdout)

    def test_a_call_in_the_trailing_closure_of_announcing_passes(self):
        self.write("DashWallet/Sources/B.swift",
                   "_ = try await IdentityTopUpDidComplete.announcing(\n"
                   "    walletId: w, network: n, identityId: id,\n"
                   "    suppliedCredits: c) {\n"
                   "    if x { try await wallet.topUpIdentityFromAddresses(identityId: id) }\n"
                   "    else { try await wallet.topUpIdentityWithFunding(identityId: id) }\n"
                   "}\n")
        self.assertEqual(self.run_guard().returncode, 0)

    def test_a_call_passed_as_the_closure_argument_of_announcing_passes(self):
        self.write("DashWallet/Sources/C.swift",
                   "_ = try await IdentityTopUpDidComplete.announcing(walletId: w, network: n, identityId: id,\n"
                   "    suppliedCredits: c, { try await wallet.resumeTopUpWithAssetLock(identityId: id) })\n")
        self.assertEqual(self.run_guard().returncode, 0)

    def test_a_closure_bound_by_name_is_not_exempt_even_when_passed_to_announcing(self):
        # Two bindings share the name; only one is passed, and the other runs directly.
        self.write("DashWallet/Sources/F.swift",
                   "func announced() async throws {\n"
                   "    let resume = {\n"
                   "        try await wallet.resumeTopUpWithAssetLock(identityId: id)\n"
                   "    }\n"
                   "    _ = try await IdentityTopUpDidComplete.announcing(walletId: w, network: n, identityId: id,\n"
                   "        suppliedCredits: c, resume)\n"
                   "}\n"
                   "func direct() async throws {\n"
                   "    let resume = {\n"
                   "        try await wallet.resumeTopUpWithAssetLock(identityId: id)\n"
                   "    }\n"
                   "    _ = try await resume()\n"
                   "}\n")
        res = self.run_guard()
        self.assertEqual(res.returncode, 1)
        self.assertIn("F.swift:3: resumeTopUpWithAssetLock outside", res.stdout)
        self.assertIn("F.swift:10: resumeTopUpWithAssetLock outside", res.stdout)

    def test_a_reasoned_marker_exempts_only_the_call_below_it(self):
        self.write("DashWallet/Sources/G.swift",
                   "if known {\n"
                   "    _ = try await IdentityTopUpDidComplete.announcing(walletId: w, network: n, identityId: id,\n"
                   "        suppliedCredits: c) { try await wallet.resumeTopUpWithAssetLock(identityId: id) }\n"
                   "} else {\n"
                   "    // top-up not announced: nothing bounds its credits.\n"
                   "    _ = try await wallet.resumeTopUpWithAssetLock(identityId: id)\n"
                   "    _ = try await wallet.resumeTopUpWithAssetLock(identityId: id)\n"
                   "}\n")
        res = self.run_guard()
        self.assertEqual(res.returncode, 1)
        self.assertIn("G.swift:7: resumeTopUpWithAssetLock outside", res.stdout)
        self.assertNotIn("G.swift:6:", res.stdout)
        self.assertNotIn("G.swift:3:", res.stdout)

    def test_a_marker_without_a_reason_does_not_exempt(self):
        self.write("DashWallet/Sources/H.swift",
                   "// top-up not announced:\n"
                   "_ = try await wallet.resumeTopUpWithAssetLock(identityId: id)\n")
        res = self.run_guard()
        self.assertEqual(res.returncode, 1)
        self.assertIn("H.swift:2: resumeTopUpWithAssetLock outside", res.stdout)

    def test_deprecated_and_shielded_top_ups_are_checked(self):
        self.write("DashWallet/Sources/I.swift",
                   "_ = try await wallet.topUpFromAddresses(identityId: id)\n"
                   "_ = try await wallet.topUpExternalIdentityFromAddresses(identityId: id)\n"
                   "try await manager.shieldedIdentityTopUpFromPool(walletId: w, identityId: id)\n")
        res = self.run_guard()
        self.assertEqual(res.returncode, 1)
        self.assertIn("I.swift:1: topUpFromAddresses outside", res.stdout)
        self.assertIn("I.swift:2: topUpExternalIdentityFromAddresses outside", res.stdout)
        self.assertIn("I.swift:3: shieldedIdentityTopUpFromPool outside", res.stdout)

    def test_a_call_after_the_announcing_closure_fails(self):
        self.write("DashWallet/Sources/D.swift",
                   "_ = try await IdentityTopUpDidComplete.announcing(walletId: w, network: n, identityId: id,\n"
                   "    suppliedCredits: c) { try await wallet.topUpIdentityFromAddresses(identityId: id) }\n"
                   "_ = try await wallet.topUpIdentityFromAddresses(identityId: id)\n")
        res = self.run_guard()
        self.assertEqual(res.returncode, 1)
        self.assertIn("D.swift:3: topUpIdentityFromAddresses outside", res.stdout)
        self.assertNotIn("D.swift:2:", res.stdout)

    def test_the_profile_sheet_execute_path_passes_and_only_there(self):
        body = ("private func executeTopUp() async -> UInt64? {\n"
                "    return try await wallet.topUpIdentityWithFunding(identityId: id)\n"
                "}\n"
                "private func topUpFromShielded() async throws -> UInt64 {\n"
                "    try await wallet.topUpIdentityFromAddresses(identityId: id)\n"
                "}\n"
                "func other() async throws {\n"
                "    _ = try await wallet.topUpIdentityFromAddresses(identityId: id)\n"
                "}\n")
        self.write("DashWallet/Sources/UI/SDKIdentityProfileSheet.swift", body)
        self.write("DashWallet/Sources/Elsewhere.swift", body)
        res = self.run_guard()
        self.assertEqual(res.returncode, 1)
        self.assertIn("SDKIdentityProfileSheet.swift:8: topUpIdentityFromAddresses outside", res.stdout)
        self.assertNotIn("SDKIdentityProfileSheet.swift:2:", res.stdout)
        self.assertNotIn("SDKIdentityProfileSheet.swift:5:", res.stdout)
        self.assertIn("Elsewhere.swift:2:", res.stdout)
        self.assertIn("Elsewhere.swift:5:", res.stdout)

    def test_comments_and_strings_do_not_count(self):
        self.write("DashWallet/Sources/E.swift",
                   "// wallet.topUpIdentityWithFunding(identityId: id)\n"
                   "/* wallet.resumeTopUpWithAssetLock( */\n"
                   'let s = "wallet.topUpIdentityFromAddresses("\n')
        self.assertEqual(self.run_guard().returncode, 0)

    def test_the_repository_passes(self):
        res = self.run_guard(ROOT)
        self.assertEqual(res.returncode, 0, res.stdout)


if __name__ == "__main__":
    unittest.main()
