"""Lock Screen Explorer mode of lock-embers.sh: an Afterburn design in ~/.config/omarchy/lock-designs, chosen over the
explorer's IPC, and never an edit to the explorer's own files."""
import unittest

from support import Sandbox

EXPLORER = "io.github.sirjul1337.lock-explorer"

# `omarchy-shell lock ...` as Lock Screen Explorer answers it: the current design lives in $SB/design. setDesign only
# knows my-afterburn once lock-designs/Afterburn.qml exists (the explorer's rescan lists files in that folder).
SHELL_STUB = r'''#!/bin/bash
echo "omarchy-shell $*" >> "$SB/calls.log"
[[ $1 == lock ]] || exit 0
[[ -f $SB/ipc-down ]] && exit 1   # the shell is not answering
case $2 in
  design) cat "$SB/design" ;;
  rescanDesigns) echo ok ;;
  setDesign)
    if [[ $3 == my-afterburn && ! -f $HOME/.config/omarchy/lock-designs/Afterburn.qml ]]; then echo unknown-design
    else echo "$3" > "$SB/design"; echo ok; fi ;;
esac
'''


class LockExplorerTests(unittest.TestCase):
    def sandbox(self, design="editorial"):
        sb = Sandbox()
        self.addCleanup(sb.cleanup)
        (sb.bin / "omarchy-shell").write_text(SHELL_STUB)
        sb.write_state_text(sb.root / "design", design + "\n")
        sb.set_plugin("omarchy.lock", "disabled")
        sb.add_user_plugin(EXPLORER)
        self.explorer_dir = sb.plugins_dir / EXPLORER
        self.explorer_files = sorted(p.name for p in self.explorer_dir.iterdir())
        return sb

    def design(self, sb):
        return (sb.root / "design").read_text().strip()

    def designs(self, sb):
        return sb.home / ".config/omarchy/lock-designs"

    def test_install_writes_the_design_selects_it_and_remembers_the_old_one(self):
        sb = self.sandbox()
        r = sb.lock("install")
        self.assertEqual(r.returncode, 0, r.stderr)
        d = self.designs(sb)
        self.assertTrue((d / "Afterburn.qml").read_text().startswith("// afterburn:lock-explorer"))
        self.assertTrue((d / "afterburn/EmberLayer.qml").is_file())
        self.assertEqual(len(list((d / "afterburn").glob("embers.*/Embers.qml"))), 1)
        self.assertEqual(sb.marker.read_text(), "mode=explorer\n")
        self.assertEqual((sb.state_dir / "lock-explorer-prev").read_text(), "editorial\n")
        self.assertEqual(self.design(sb), "my-afterburn")
        # No clone, no enable/disable, and the explorer's folder untouched.
        self.assertFalse((sb.plugins_dir / "afterburn.lock").exists())
        self.assertEqual(sb.enabled_locks(), [EXPLORER])
        self.assertEqual(sorted(p.name for p in self.explorer_dir.iterdir()), self.explorer_files)

    def test_install_refuses_a_design_file_that_is_not_ours(self):
        sb = self.sandbox()
        sb.write_state_text(self.designs(sb) / "Afterburn.qml", "// my own design\n")
        r = sb.lock("install")
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual((self.designs(sb) / "Afterburn.qml").read_text(), "// my own design\n")
        self.assertEqual(self.design(sb), "editorial")

    def test_recolor_writes_new_embers_into_the_design_folder(self):
        sb = self.sandbox()
        sb.lock("install")
        r = sb.lock("recolor", "112233", "445566", "778899", "fall")
        self.assertEqual(r.returncode, 0, r.stderr)
        embers = list((self.designs(sb) / "afterburn").glob("embers.*/Embers.qml"))
        self.assertEqual(len(embers), 1)
        text = embers[0].read_text()
        self.assertIn("445566", text)
        self.assertNotIn("ff5a1f", text)

    def test_park_and_unpark_swap_designs(self):
        sb = self.sandbox()
        sb.lock("install")
        sb.write_state_text(sb.home / ".local/state/omarchy/current/theme.name", "nord\n")
        self.assertEqual(sb.lock("park").returncode, 0)
        self.assertEqual(self.design(sb), "editorial")
        sb.write_state_text(sb.home / ".local/state/omarchy/current/theme.name", "afterburn\n")
        self.assertEqual(sb.lock("unpark").returncode, 0)
        self.assertEqual(self.design(sb), "my-afterburn")

    def test_a_design_picked_while_parked_stays(self):
        sb = self.sandbox()
        sb.lock("install")
        sb.lock("park")
        sb.write_state_text(sb.root / "design", "zen\n")
        sb.lock("unpark")
        self.assertEqual(self.design(sb), "zen")
        self.assertFalse((sb.state_dir / "lock-parked").exists())

    def test_uninstall_restores_the_old_design_and_removes_ours(self):
        sb = self.sandbox()
        sb.lock("install")
        r = sb.lock("uninstall")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.design(sb), "editorial")
        self.assertFalse((self.designs(sb) / "Afterburn.qml").exists())
        self.assertFalse((self.designs(sb) / "afterburn").exists())
        self.assertFalse(sb.marker.exists())
        self.assertEqual(sb.enabled_locks(), [EXPLORER])

    def test_stock_lock_still_gets_the_clone(self):
        sb = Sandbox()
        self.addCleanup(sb.cleanup)
        r = sb.lock("install")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue((sb.plugins_dir / "afterburn.lock").is_dir())
        self.assertIn("clone_id=afterburn.lock", sb.marker.read_text())

    # --- review follow-ups ---------------------------------------------------------------------------------------
    def test_target_says_which_lock_install_acts_on(self):
        sb = self.sandbox()
        self.assertEqual(sb.lock("target").stdout.strip(), "explorer")
        plain = Sandbox()
        self.addCleanup(plain.cleanup)
        self.assertEqual(plain.lock("target").stdout.strip(), "clone")

    def test_a_clone_from_before_is_removed_when_moving_to_the_explorer(self):
        sb = Sandbox()
        self.addCleanup(sb.cleanup)
        (sb.bin / "omarchy-shell").write_text(SHELL_STUB)
        sb.write_state_text(sb.root / "design", "editorial\n")
        self.assertEqual(sb.lock("install").returncode, 0)
        self.assertTrue((sb.plugins_dir / "afterburn.lock").is_dir())
        sb.set_plugin("afterburn.lock", "disabled")
        sb.add_user_plugin(EXPLORER)
        r = sb.lock("install")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertFalse((sb.plugins_dir / "afterburn.lock").exists())
        self.assertEqual(sb.marker.read_text(), "mode=explorer\n")
        self.assertEqual(sb.enabled_locks(), [EXPLORER])

    def test_back_on_the_stock_lock_install_clones_and_drops_our_design(self):
        sb = self.sandbox()
        sb.lock("install")
        sb.set_plugin(EXPLORER, "disabled")
        sb.set_plugin("omarchy.lock", "enabled")
        self.assertEqual(sb.lock("target").stdout.strip(), "clone")
        r = sb.lock("install")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertFalse((self.designs(sb) / "Afterburn.qml").exists())
        self.assertTrue((sb.plugins_dir / "afterburn.lock").is_dir())
        self.assertIn("clone_id=afterburn.lock", sb.marker.read_text())

    def test_silent_explorer_at_install_selects_nothing_and_remembers_nothing(self):
        sb = self.sandbox()
        (sb.root / "ipc-down").touch()
        r = sb.lock("install")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue((self.designs(sb) / "Afterburn.qml").exists())
        self.assertFalse((sb.state_dir / "lock-explorer-prev").exists())
        self.assertNotIn("setDesign", "".join(sb.call_log()))

    def test_silent_explorer_keeps_the_park_record(self):
        sb = self.sandbox()
        sb.lock("install")
        sb.lock("park")
        (sb.root / "ipc-down").touch()
        self.assertNotEqual(sb.lock("unpark").returncode, 0)
        self.assertTrue((sb.state_dir / "lock-parked").exists())
        (sb.root / "ipc-down").unlink()
        self.assertEqual(sb.lock("unpark").returncode, 0)
        self.assertEqual(self.design(sb), "my-afterburn")

    def test_silent_explorer_at_uninstall_removes_nothing(self):
        sb = self.sandbox()
        sb.lock("install")
        (sb.root / "ipc-down").touch()
        self.assertNotEqual(sb.lock("uninstall").returncode, 0)
        self.assertTrue((self.designs(sb) / "Afterburn.qml").exists())
        self.assertTrue(sb.marker.exists())

    def test_an_embers_folder_that_is_not_ours_is_left_alone(self):
        sb = self.sandbox()
        mine = self.designs(sb) / "afterburn" / "notes.txt"
        sb.write_state_text(mine, "mine\n")
        self.assertNotEqual(sb.lock("install").returncode, 0)
        self.assertEqual(mine.read_text(), "mine\n")
        self.assertFalse((self.designs(sb) / "Afterburn.qml").exists())

    def test_the_import_follows_the_explorer_folder_name(self):
        sb = Sandbox()
        self.addCleanup(sb.cleanup)
        (sb.bin / "omarchy-shell").write_text(SHELL_STUB)
        sb.write_state_text(sb.root / "design", "editorial\n")
        sb.set_plugin("omarchy.lock", "disabled")
        sb.add_user_plugin(EXPLORER, folder="lock-explorer")
        self.assertEqual(sb.lock("install").returncode, 0)
        self.assertIn('import "../plugins/lock-explorer/designs"', (self.designs(sb) / "Afterburn.qml").read_text())

    def test_a_failed_restore_at_uninstall_keeps_everything_for_a_retry(self):
        sb = self.sandbox()
        sb.lock("install")
        sb.write_state_text(sb.state_dir / "lock-explorer-prev", "vanished\n")
        stub = (sb.bin / "omarchy-shell").read_text().replace("setDesign)", "setDesign)\n    [[ $3 == vanished ]] && { echo unknown-design; exit 0; }", 1)
        (sb.bin / "omarchy-shell").write_text(stub)
        r = sb.lock("uninstall")
        self.assertNotEqual(r.returncode, 0)
        self.assertTrue((self.designs(sb) / "Afterburn.qml").exists())
        self.assertTrue((sb.state_dir / "lock-explorer-prev").exists())
        self.assertEqual(self.design(sb), "my-afterburn")


if __name__ == "__main__":
    unittest.main()
