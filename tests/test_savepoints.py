"""Issue #7: cursor-fx savepoints live in Afterburn's state folder, not in your home folder."""
import unittest

from support import REPO, UNINSTALL, Sandbox

HOOK = REPO / "extras/afterburn-theme-set-hook"
# A cursor-fx that records where it would write its savepoint.
CFX = '#!/bin/bash\necho "cursor-fx $* savepoints=${CURSOR_FX_SAVEPOINTS:-unset}" >> "$SB/calls.log"\n'


class Savepoints(unittest.TestCase):
    def setUp(self):
        self.sb = Sandbox()
        self.addCleanup(self.sb.cleanup)
        self.sb.use_stubs(["afterburn"])
        stub = self.sb.root / "bin" / "cursor-fx"
        stub.write_text(CFX)
        stub.chmod(0o755)
        self.old = self.sb.home / "ghostty-savepoints"
        self.new = self.sb.state_dir / "ghostty-savepoints"

    def savepoint(self, base, name):
        d = base / name
        d.mkdir(parents=True)
        (d / "ghostty-config").write_text(f"{name}\n")
        return d

    def hook(self, **env):
        r = self.sb.run(["/bin/bash", str(HOOK), "afterburn"], **env)
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_hook_moves_old_savepoints_and_points_cursor_fx_at_state(self):
        self.savepoint(self.old, "20261105-213202-before-install")
        self.savepoint(self.old, "20261112-204552-before-cursor-fx-lightning")
        self.hook()
        self.assertFalse(self.old.exists())
        self.assertEqual((self.new / "20261105-213202-before-install" / "ghostty-config").read_text(),
                         "20261105-213202-before-install\n")
        self.assertTrue((self.new / "20261112-204552-before-cursor-fx-lightning").is_dir())
        self.assertIn(f"cursor-fx embers savepoints={self.new}", self.sb.call_log())

    def test_other_files_and_name_clashes_are_left_alone(self):
        self.savepoint(self.old, "20261105-213202-before-install")
        self.savepoint(self.new, "20261105-213202-before-install").joinpath("ghostty-config").write_text("kept\n")
        (self.old / "notes.txt").write_text("mine\n")
        self.hook()
        self.assertEqual((self.old / "notes.txt").read_text(), "mine\n")
        self.assertTrue((self.old / "20261105-213202-before-install").is_dir())
        self.assertEqual((self.new / "20261105-213202-before-install" / "ghostty-config").read_text(), "kept\n")

    def test_your_own_savepoint_folder_wins(self):
        mine = self.sb.root / "my-savepoints"
        self.savepoint(self.old, "20261105-213202-before-install")
        self.hook(CURSOR_FX_SAVEPOINTS=str(mine))
        self.assertTrue((mine / "20261105-213202-before-install").is_dir())
        self.assertIn(f"cursor-fx embers savepoints={mine}", self.sb.call_log())

    def test_uninstall_keeps_the_savepoints(self):
        self.savepoint(self.new, "20261105-213202-before-install")
        r = self.sb.run(["/bin/bash", str(UNINSTALL)])
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertTrue((self.new / "20261105-213202-before-install").is_dir())
        self.assertIn("kept your Ghostty config backups", r.stdout)


    def test_a_failed_move_or_a_link_never_stops_a_strict_caller(self):
        from support import THEME_SH
        self.savepoint(self.old, "20261105-213202-before-install")
        target = self.savepoint(self.sb.root, "elsewhere")
        (self.old / "20261106-000000-before-cursor-fx-katana").symlink_to(target)
        self.new.mkdir(parents=True)
        self.new.chmod(0o500)                      # the move fails: permission denied
        self.addCleanup(self.new.chmod, 0o755)
        r = self.sb.run(["/bin/bash", "-c", f'set -euo pipefail; . "{THEME_SH}"; ab_move_savepoints; echo AFTER'])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("AFTER", r.stdout)
        self.assertTrue((self.old / "20261105-213202-before-install").is_dir())
        self.assertTrue((self.old / "20261106-000000-before-cursor-fx-katana").is_symlink())

if __name__ == "__main__":
    unittest.main()
