import os
import shutil
import subprocess
import unittest

try:  # `unittest discover -s tests` and `unittest tests.test_x` both work
    from support import LOCK_SH, LOCK_VIEW, REPO, UNINSTALL, Sandbox
except ImportError:
    from tests.support import LOCK_SH, LOCK_VIEW, REPO, UNINSTALL, Sandbox


LOADER = REPO / "extras" / "lock" / "EmberLoader.qml"


class LockEmbersBase(unittest.TestCase):
    def make(self, user="alice"):
        sb = Sandbox(user)
        self.addCleanup(sb.cleanup)
        return sb

    def embers(self, clone):
        """The clone's one embers.<n>/Embers.qml (the embers the loader shows)."""
        versions = sorted(clone.glob("embers.*"))
        self.assertEqual(len(versions), 1, versions)
        return versions[0] / "Embers.qml"


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
        self.assertEqual(list(sb.plugins_dir.glob(".afterburn.lock.bak.*")), [], "and no backup of it is left")

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


class UninstallLeavesOtherLocksTests(LockEmbersBase):
    def enables(self, sb):
        return [c for c in sb.call_log() if "omarchy-plugin-enable" in c]

    def installed(self, user="alice"):
        sb = self.make(user)
        self.assertEqual(sb.lock("install").returncode, 0)
        sb.set_plugin("afterburn.lock", "disabled")      # the user moved on from our clone
        return sb

    def test_third_party_lock_chosen_later_survives_uninstall(self):
        sb = self.installed()
        sb.add_user_plugin("hello.lock", "enabled", lock=True)
        r = sb.lock("uninstall")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(sb.enabled_locks(), ["hello.lock"])
        self.assertFalse(any("omarchy.lock" in c for c in self.enables(sb)), sb.call_log())
        self.assertFalse((sb.plugins_dir / "afterburn.lock").exists())

    def test_active_clone_gives_the_builtin_back(self):
        sb = self.make("alice")
        self.assertEqual(sb.lock("install").returncode, 0)
        r = sb.lock("uninstall")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(sb.enabled_locks(), ["omarchy.lock"])

    def test_builtin_already_restored_by_the_remove_is_not_enabled_again(self):
        sb = self.make("alice")
        self.assertEqual(sb.lock("install").returncode, 0)    # the clone is the active lock
        r = sb.lock("uninstall")                               # omarchy-plugin-remove switches omarchy.lock back on
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(sb.enabled_locks(), ["omarchy.lock"])
        self.assertEqual(self.enables(sb), [], sb.call_log())
        self.assertNotIn("no lock screen is enabled", r.stdout + r.stderr)

    def test_a_failed_enable_still_removes_the_marker(self):
        sb = self.installed()
        sb.set_plugin("omarchy.lock", "disabled")             # nothing is enabled, so uninstall tries to enable it
        r = sb.lock("uninstall", STUB_ENABLE_FAIL="1")
        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)   # uninstall.sh then says "not restored"
        self.assertFalse(sb.marker.exists(), r.stdout + r.stderr)
        self.assertFalse((sb.plugins_dir / "afterburn.lock").exists())

    def test_cannot_tell_touches_no_lock(self):
        sb = self.installed()
        sb.add_user_plugin("lockscreen-x", "enabled", manifest="broken")
        r = sb.lock("uninstall")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(self.enables(sb), [], sb.call_log())
        self.assertFalse((sb.plugins_dir / "afterburn.lock").exists())

    def test_uninstall_leaves_no_backup_of_the_clone(self):  # E2E I4
        sb = self.make("alice")
        self.assertEqual(sb.lock("install").returncode, 0)
        old = sb.plugins_dir / ".afterburn.lock.bak.20200101000000"   # one the user made by hand: not ours to delete
        other = sb.plugins_dir / ".other.bak.x"
        for d in (old, other):
            d.mkdir()
        r = sb.lock("uninstall")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertFalse((sb.plugins_dir / "afterburn.lock").exists())
        self.assertEqual(sorted(p.name for p in sb.plugins_dir.glob(".*")), [old.name, other.name])
        self.assertNotIn("Backup at", r.stdout)


class FailedWriteTests(LockEmbersBase):
    """A write that fails (a full disk; `ulimit -f 1` caps every file at 1 KiB) leaves the active lock as it was."""

    def files(self, d):
        return {str(p.relative_to(d)): p.read_bytes() for p in d.rglob("*") if p.is_file()}

    def test_failed_refresh_keeps_the_clone(self):  # codex-verified #2
        sb = self.make("alice")
        self.assertEqual(sb.lock("install").returncode, 0)
        self.assertEqual(sb.lock("recolor", "aaaaaa", "bbbbbb", "cccccc", "spark").returncode, 0)
        clone = sb.plugins_dir / "afterburn.lock"
        before = self.files(clone)
        r = sb.run(["/bin/bash", "-c", f'ulimit -f 1; exec /bin/bash "{LOCK_SH}" install'])   # writes the orange back
        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(self.files(clone), before, "no file changed and no temp file left")
        self.assertEqual(sb.enabled_locks(), ["afterburn.lock"])

    def test_failed_layer_insert_keeps_lock_view(self):
        sb = self.make("alice")
        view = sb.root / "view" / "LockView.qml"
        view.parent.mkdir()
        view.write_text(LOCK_VIEW.replace("Item {\n", "Item {\n" + "    // a long lock view\n" * 80))
        before = self.files(view.parent)
        r = sb.run(["/bin/bash", "-c", f'source "{LOCK_SH}"; ulimit -f 1; insert_layer "{view}" && echo INSERTED'])
        self.assertNotIn("INSERTED", r.stdout, r.stdout + r.stderr)
        self.assertEqual(self.files(view.parent), before, "LockView.qml unchanged and no temp file left")


class LiveRecolorTests(LockEmbersBase):
    """E2E I3. The shell keeps the lock service, and every QML type it built, for the whole session, and Quickshell keeps
    the text of every QML file it has loaded, by path. So the clone's EmberLayer.qml is a loader, and each set of embers
    goes into a new embers.<n>/Embers.qml; the loader shows the newest one each time the lock shows."""

    def test_install_and_recolor_write_a_new_embers_folder(self):
        sb = self.make("alice")
        self.assertEqual(sb.lock("install").returncode, 0)
        clone = sb.plugins_dir / "afterburn.lock"
        self.assertEqual((clone / "EmberLayer.qml").read_bytes(), LOADER.read_bytes())
        first = self.embers(clone)
        self.assertEqual(first.read_bytes(), (REPO / "extras/lock/EmberLayer.qml").read_bytes())
        (clone / "Embers.qml").write_text("// pre-release layout\n")
        r = sb.lock("recolor", "aaaaaa", "bbbbbb", "cccccc", "spark")
        self.assertFalse((clone / "Embers.qml").exists(), "the pre-release root Embers.qml is gone")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        spark = (REPO / "extras/lock/styles/spark.qml").read_text()
        second = self.embers(clone)
        self.assertNotEqual(second.parent.name, first.parent.name, "a new path, so the shell reads it")
        self.assertEqual(second.read_text(),
                         spark.replace("ffc48a", "aaaaaa").replace("ff5a1f", "bbbbbb").replace("7a3e16", "cccccc"))
        self.assertEqual(sb.lock("recolor", "aaaaaa", "bbbbbb", "cccccc", "spark").returncode, 0)
        self.assertEqual(self.embers(clone), second, "the same embers again make no new folder")
        self.assertEqual([p.name for p in clone.iterdir() if p.name.startswith(".")], [], "no temp left")
        self.assertEqual((clone / "EmberLayer.qml").read_bytes(), LOADER.read_bytes())

    def test_concurrent_recolours_always_leave_the_newest_folder(self):
        """Two quick theme switches run two recolours at once: one must not delete the other's new folder."""
        sb = self.make("alice")
        d = sb.root / "clone"
        d.mkdir()
        (sb.root / "a.qml").write_text("// a\n")
        (sb.root / "b.qml").write_text("// b\n")
        script = (f'source "{LOCK_SH}"; for i in {{1..30}}; do '
                  f'put_embers "{d}" "{sb.root}/a.qml" & put_embers "{d}" "{sb.root}/b.qml" & wait; '
                  f'echo "round $i: $(find "{d}" -mindepth 1 -maxdepth 1 -name "embers.*" | wc -l)"; '
                  f'cp "{sb.root}/a.qml" "{sb.root}/c.qml"; cp "{sb.root}/b.qml" "{sb.root}/a.qml"; cp "{sb.root}/c.qml" "{sb.root}/b.qml"; done')
        r = sb.run(["/bin/bash", "-c", script])
        self.assertEqual(r.returncode, 0, r.stderr)
        rounds = [line for line in r.stdout.splitlines() if line.startswith("round")]
        self.assertEqual(len(rounds), 30, r.stdout + r.stderr)
        self.assertEqual([x for x in rounds if x.endswith(": 0")], [], "a round left no embers at all")
        newest = sorted(d.glob("embers.*"))[-1]
        self.assertIn((newest / "Embers.qml").read_text(), ("// a\n", "// b\n"))

    @unittest.skipUnless(shutil.which("qml6"), "needs Qt's qml6 runner")
    def test_loader_shows_the_newest_embers_without_a_restart(self):
        """Real Qt, offscreen. As in Omarchy's LockView, the layer sits in a Rectangle below the view that has
        loadBackground. Showing again with nothing new reuses the URL (no new copy per lock); after a new
        embers.<n> folder replaces the old one, as recolor does, the next show loads the new embers."""
        sb = self.make("alice")
        d = sb.root / "qml"
        (d / "embers.1").mkdir(parents=True)
        (d / "styles").mkdir()          # any other folder (it sorts after embers.*) is never picked
        (d / "styles" / "Embers.qml").write_text('import QtQuick\nItem { property string tag: "styles" }\n')
        shutil.copy(LOADER, d / "EmberLayer.qml")
        (d / "embers.1" / "Embers.qml").write_text('import QtQuick\nItem { property string tag: "old" }\n')
        (d / "LockView.qml").write_text(
            "import QtQuick\nItem {\n  property bool loadBackground: false\n  property alias embers: embers\n"
            "  Rectangle {\n    anchors.fill: parent\n    EmberLayer { id: embers; anchors.fill: parent }\n  }\n}\n")
        (d / "Main.qml").write_text("""import QtQuick
import QtQuick.Window
Window {
  id: w
  width: 64; height: 48; visible: true
  LockView { id: v; anchors.fill: parent }
  function tag() { return v.embers.item ? v.embers.item.tag + " " + v.embers.item.width + " " + v.embers.source : "none" }
  property int i: 0
  property var steps: [
    function() { console.log("HIDDEN", tag()); v.loadBackground = true },
    function() { console.log("SHOWN", tag()); v.loadBackground = false },
    function() { v.loadBackground = true },
    function() { console.log("RESHOWN", tag()); v.loadBackground = false },   // the test writes embers.2 now
    function() {}, function() {}, function() {}, function() {},
    function() { v.loadBackground = true },
    function() { console.log("AGAIN", tag()); Qt.quit() } ]
  Timer { interval: 150; repeat: true; running: true; onTriggered: w.i < w.steps.length ? w.steps[w.i++]() : Qt.quit() }
}
""")
        env = {"PATH": os.environ.get("PATH", "/usr/bin"), "HOME": str(sb.home), "QT_QPA_PLATFORM": "offscreen",
               "QT_FORCE_STDERR_LOGGING": "1", "XDG_CACHE_HOME": str(sb.root / "cache"),
               "XDG_RUNTIME_DIR": str(sb.root / "run"), "LANG": "C.UTF-8"}
        p = subprocess.Popen(["qml6", str(d / "Main.qml")], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             text=True, stdin=subprocess.DEVNULL)
        self.addCleanup(p.stdout.close)
        self.addCleanup(p.kill)       # cleanups run last-in first-out: kill, then close the pipe
        lines = {}
        for line in p.stdout:
            word, _, rest = line.removeprefix("qml: ").partition(" ")
            lines[word] = rest.strip()
            if word == "RESHOWN":
                (d / ".new").mkdir()
                (d / ".new" / "Embers.qml").write_text('import QtQuick\nItem { property string tag: "new" }\n')
                os.rename(d / ".new", d / "embers.2")
                shutil.rmtree(d / "embers.1")
        p.wait(timeout=30)
        self.assertEqual(lines.get("HIDDEN"), "none", lines)
        self.assertTrue(lines.get("SHOWN", "").startswith("old 64 "), lines)
        self.assertEqual(lines.get("RESHOWN"), lines["SHOWN"], "nothing new keeps the URL")
        self.assertTrue(lines.get("AGAIN", "").startswith("new 64 "), lines)
        self.assertIn("/embers.2/Embers.qml", lines["AGAIN"])


class BackwardsCompatTests(LockEmbersBase):
    """Installs made before the id change used ~/.config/omarchy/plugins/<user>.lock."""

    def test_recolor_finds_an_old_id_install(self):
        sb = self.make("alice")
        sb.add_legacy_clone("alice.lock")
        sb.write_state_text(sb.marker, "")             # the old marker was an empty file
        r = sb.lock("recolor", "aaaaaa", "bbbbbb", "cccccc")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        clone = sb.plugins_dir / "alice.lock"
        text = self.embers(clone).read_text()
        self.assertIn("bbbbbb", text)
        self.assertNotIn("ff5a1f", text)
        self.assertEqual((clone / "EmberLayer.qml").read_bytes(), LOADER.read_bytes(), "the old layer becomes the loader")

    def test_uninstall_removes_an_old_id_install_and_restores_the_builtin(self):
        sb = self.make("alice")
        sb.add_legacy_clone("alice.lock")
        sb.write_state_text(sb.marker, "")
        r = sb.lock("uninstall")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertFalse((sb.plugins_dir / "alice.lock").exists())
        self.assertEqual(sb.enabled_locks(), ["omarchy.lock"])
        self.assertEqual(list(sb.plugins_dir.glob(".alice.lock.bak.*")), [])

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
