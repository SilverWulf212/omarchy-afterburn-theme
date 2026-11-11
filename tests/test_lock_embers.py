import unittest

try:  # `unittest discover -s tests` and `unittest tests.test_x` both work
    from support import LOCK_SH, REPO, UNINSTALL, Sandbox
except ImportError:
    from tests.support import LOCK_SH, REPO, UNINSTALL, Sandbox


class LockEmbersBase(unittest.TestCase):
    def make(self, user="alice"):
        sb = Sandbox(user)
        self.addCleanup(sb.cleanup)
        return sb


class InstallIdTests(LockEmbersBase):
    def test_user_omarchy_never_gets_the_builtin_id(self):  # issue #5
        sb = self.make("omarchy")
        r = sb.lock("install")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertFalse((sb.plugins_dir / "omarchy.lock").exists())
        self.assertTrue((sb.plugins_dir / "afterburn.lock").is_dir())
        self.assertEqual(sb.enabled_locks(), ["afterburn.lock"])
        self.assertIn("clone_id=afterburn.lock", sb.marker.read_text())
        self.assertIn("EmberLayer {", (sb.plugins_dir / "afterburn.lock" / "LockView.qml").read_text())

    def test_ordinary_user_gets_the_same_id(self):
        sb = self.make("alice")
        self.assertEqual(sb.lock("install").returncode, 0)
        self.assertEqual(sb.enabled_locks(), ["afterburn.lock"])
        self.assertFalse((sb.plugins_dir / "alice.lock").exists())

    def test_install_twice_is_idempotent(self):
        sb = self.make("omarchy")
        self.assertEqual(sb.lock("install").returncode, 0)
        r = sb.lock("install")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        view = (sb.plugins_dir / "afterburn.lock" / "LockView.qml").read_text()
        self.assertEqual(view.count("EmberLayer {"), 1)
        self.assertEqual(sb.enabled_locks(), ["afterburn.lock"])

    def test_reserved_id_is_refused_before_anything_changes(self):
        sb = self.make("alice")
        r = sb.lock("install", LOCK_EMBERS_CLONE_USER="omarchy")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("reserved", r.stdout + r.stderr)
        self.assertFalse(any("omarchy-plugin-clone" in c for c in sb.call_log()))
        self.assertEqual(sb.enabled_locks(), ["omarchy.lock"])

    def test_tampered_marker_with_a_reserved_id_is_ignored(self):
        sb = self.make("alice")
        sb.write_state_text(sb.marker, "clone_id=omarchy.lock\n")
        r = sb.lock("install")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertTrue((sb.plugins_dir / "afterburn.lock").is_dir())
        self.assertEqual(sb.enabled_locks(), ["afterburn.lock"])


class FailSafeTests(LockEmbersBase):
    """If anything after the built-in lock was disabled fails, the built-in comes back."""

    def assert_builtin_back(self, sb, r):
        self.assertNotEqual(r.returncode, 0, "the install should report failure")
        self.assertEqual(sb.enabled_locks(), ["omarchy.lock"], r.stdout + r.stderr)
        self.assertIn("omarchy.lock", r.stdout + r.stderr)
        self.assertFalse(sb.marker.exists(), "no marker for a clone that does not exist")

    def test_clone_fails_after_switching_away(self):
        sb = self.make("alice")
        self.assert_builtin_back(sb, sb.lock("install", STUB_CLONE_FAIL="mid"))

    def test_clone_fails_before_doing_anything(self):
        sb = self.make("alice")
        self.assert_builtin_back(sb, sb.lock("install", STUB_CLONE_FAIL="pre"))

    def test_clone_dir_missing_afterwards(self):
        sb = self.make("alice")
        self.assert_builtin_back(sb, sb.lock("install", STUB_CLONE_NODIR="1"))

    def test_patch_step_fails(self):
        sb = self.make("alice")
        r = sb.lock("install", STUB_CLONE_BREAK_ANCHOR="1")
        self.assert_builtin_back(sb, r)
        self.assertFalse((sb.plugins_dir / "afterburn.lock").exists(), "the half-made clone is removed")

    def test_validation_fails(self):
        sb = self.make("alice")
        r = sb.lock("install", STUB_VALIDATE_FAIL="1")
        self.assert_builtin_back(sb, r)
        self.assertFalse((sb.plugins_dir / "afterburn.lock").exists())

    def test_failure_on_a_reused_clone_keeps_the_working_clone_active(self):
        sb = self.make("alice")
        self.assertEqual(sb.lock("install").returncode, 0)
        r = sb.lock("install", STUB_VALIDATE_FAIL="1")
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(sb.enabled_locks(), ["afterburn.lock"])
        self.assertTrue(sb.marker.exists())

    def test_user_who_lost_every_lock_to_the_old_bug_gets_the_builtin_back(self):
        sb = self.make("omarchy")
        sb.set_plugin("omarchy.lock", "disabled")      # what the #5 victim is left with
        r = sb.lock("install")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(sb.enabled_locks(), ["afterburn.lock"])

    def test_third_party_lock_is_left_alone(self):
        sb = self.make("alice")
        sb.set_plugin("omarchy.lock", "disabled")
        sb.set_plugin("hello.lock", "enabled")
        r = sb.lock("install")
        self.assertEqual(r.returncode, 3, r.stdout + r.stderr)
        self.assertEqual(sb.enabled_locks(), ["hello.lock"])


class OtherLockDetectionTests(LockEmbersBase):
    """Is someone else's lock screen enabled? Decided from manifests, not from names or the KINDS column."""

    def assert_untouched(self, sb, r, expect_enabled):
        self.assertEqual(r.returncode, 3, r.stdout + r.stderr)
        self.assertFalse(any("omarchy-plugin-clone" in c or "omarchy-plugin-enable" in c for c in sb.call_log()),
                         sb.call_log())
        self.assertEqual(sb.enabled_locks(), expect_enabled)
        self.assertFalse((sb.plugins_dir / "afterburn.lock").exists())

    def test_third_party_lock_whose_id_does_not_end_in_lock_is_detected(self):
        for pid in ("lockscreen-x", "hello-lock-v2"):
            with self.subTest(pid=pid):
                sb = self.make("alice")
                sb.set_plugin("omarchy.lock", "disabled")
                sb.add_user_plugin(pid, "enabled", lock=True)
                self.assert_untouched(sb, sb.lock("install"), [pid])

    def test_manifest_is_found_by_its_id_when_the_folder_is_named_differently(self):
        sb = self.make("alice")
        sb.set_plugin("omarchy.lock", "disabled")
        sb.add_user_plugin("greeter", "enabled", lock=True, folder="greeter-checkout")
        self.assert_untouched(sb, sb.lock("install"), ["greeter"])

    def test_enabled_clock_is_not_mistaken_for_a_lock(self):
        # omarchy.clock is a first-party bar widget. With no lock enabled at all, the built-in comes back.
        sb = self.make("alice")
        sb.set_plugin("omarchy.lock", "disabled")
        sb.set_plugin("omarchy.clock", "enabled", lock=False)
        sb.set_plugin("omarchy.polkit", "enabled", lock=False)   # first-party, also has the capability
        r = sb.lock("install")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(sb.enabled_locks(), ["afterburn.lock"])

    def test_enabled_third_party_clock_widget_is_not_a_lock(self):
        sb = self.make("alice")
        sb.set_plugin("omarchy.lock", "disabled")
        sb.add_user_plugin("tmn73.clock", "enabled", lock=False)
        r = sb.lock("install")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(sb.enabled_locks(), ["afterburn.lock"])

    def test_unreadable_manifest_with_an_id_ending_in_lock_still_counts(self):
        for manifest in ("broken", "none"):
            with self.subTest(manifest=manifest):
                sb = self.make("alice")
                sb.set_plugin("omarchy.lock", "disabled")
                sb.add_user_plugin("hello-lock", "enabled", manifest=manifest)
                self.assert_untouched(sb, sb.lock("install"), ["hello-lock"])

    def test_unreadable_manifest_and_an_unrevealing_id_means_hands_off(self):
        sb = self.make("alice")
        sb.set_plugin("omarchy.lock", "disabled")
        sb.add_user_plugin("lockscreen-x", "enabled", manifest="broken")
        self.assert_untouched(sb, sb.lock("install"), ["lockscreen-x"])

    def test_empty_plugin_list_means_hands_off(self):
        sb = self.make("alice")
        sb.set_plugin("omarchy.lock", "disabled")
        (sb.bin / "omarchy-plugin-list").write_text("#!/bin/bash\nexit 1\n")
        r = sb.lock("install")
        self.assertEqual(r.returncode, 3, r.stdout + r.stderr)
        self.assertFalse(any("omarchy-plugin-enable" in c for c in sb.call_log()))


class BackwardsCompatTests(LockEmbersBase):
    """Installs made before the id change used ~/.config/omarchy/plugins/<user>.lock."""

    def test_recolor_finds_an_old_id_install(self):
        sb = self.make("alice")
        sb.add_legacy_clone("alice.lock")
        sb.write_state_text(sb.marker, "")             # the old marker was an empty file
        r = sb.lock("recolor", "aaaaaa", "bbbbbb", "cccccc")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        text = (sb.plugins_dir / "alice.lock" / "EmberLayer.qml").read_text()
        self.assertIn("bbbbbb", text)
        self.assertNotIn("ff5a1f", text)

    def test_uninstall_removes_an_old_id_install_and_restores_the_builtin(self):
        sb = self.make("alice")
        sb.add_legacy_clone("alice.lock")
        sb.write_state_text(sb.marker, "")
        r = sb.lock("uninstall")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertFalse((sb.plugins_dir / "alice.lock").exists())
        self.assertEqual(sb.enabled_locks(), ["omarchy.lock"])

    def test_install_reuses_an_old_id_clone_and_upgrades_the_marker(self):
        sb = self.make("alice")
        sb.add_legacy_clone("alice.lock")
        sb.write_state_text(sb.marker, "")
        r = sb.lock("install")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertFalse((sb.plugins_dir / "afterburn.lock").exists())
        self.assertFalse(any("omarchy-plugin-clone" in c for c in sb.call_log()))
        self.assertIn("clone_id=alice.lock", sb.marker.read_text())
        self.assertEqual(sb.enabled_locks(), ["alice.lock"])

    def test_the_marker_id_wins_over_the_username(self):
        sb = self.make("someone-else")
        sb.add_legacy_clone("afterburn.lock")
        sb.write_state_text(sb.marker, "clone_id=afterburn.lock\n")
        self.assertEqual(sb.lock("uninstall").returncode, 0)
        self.assertFalse((sb.plugins_dir / "afterburn.lock").exists())
        self.assertEqual(sb.enabled_locks(), ["omarchy.lock"])
        self.assertFalse(sb.marker.exists())

    def test_new_install_then_uninstall_round_trip(self):
        sb = self.make("omarchy")
        self.assertEqual(sb.lock("install").returncode, 0)
        r = sb.lock("uninstall")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(sb.enabled_locks(), ["omarchy.lock"])
        self.assertFalse(sb.marker.exists())

    def test_extras_uninstall_sh_restores_the_lock_for_both_id_styles(self):
        for legacy in (True, False):
            with self.subTest(legacy=legacy):
                sb = self.make("alice")
                if legacy:
                    sb.add_legacy_clone("alice.lock")
                    sb.write_state_text(sb.marker, "")
                else:
                    self.assertEqual(sb.lock("install").returncode, 0)
                r = sb.run(["/bin/bash", str(UNINSTALL)])
                self.assertEqual(sb.enabled_locks(), ["omarchy.lock"], r.stdout + r.stderr)
                self.assertIn("lock screen restored", r.stdout)
                self.assertFalse(sb.state_dir.exists())

    def test_install_sh_lock_step_does_not_clobber_the_marker(self):
        """Run the real step 5 text of extras/install.sh (between its '# 5.' and '# 6.' markers)."""
        sb = self.make("omarchy")
        text = (REPO / "extras" / "install.sh").read_text()
        step = text.split("# 5. Animated lock screen", 1)[1].split("# 6. Colour editions", 1)[0]
        prelude = (
            'ok() { echo "OK $*"; }; skip() { echo "SKIP $*"; }; ask() { return 0; }; o() { echo "$*"; }\n'
            f'CHANGED=(); STATE_DIR="$HOME/.local/state/afterburn"; mkdir -p "$STATE_DIR"; HERE="{REPO}/extras"\n'
            "set -euo pipefail\n# 5. Animated lock screen")
        r = sb.run(["/bin/bash", "-c", prelude + step])
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("OK lock screen animated", r.stdout)
        self.assertIn("clone_id=afterburn.lock", sb.marker.read_text())
        self.assertEqual(sb.enabled_locks(), ["afterburn.lock"])


if __name__ == "__main__":
    unittest.main()
