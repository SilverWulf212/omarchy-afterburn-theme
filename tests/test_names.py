"""One source of truth for names: edition names come from folders, cursor-fx names from one list."""
import os
import pathlib
import shutil
import subprocess
import unittest

from support import REPO, Sandbox

THEME_SH = REPO / "extras" / "afterburn-theme.sh"
INSTALL_TEXT = (REPO / "extras" / "install.sh").read_text()


class CursorFxNames(unittest.TestCase):
    def setUp(self):
        self.sb = Sandbox()
        self.addCleanup(self.sb.cleanup)

    def valid(self, value):
        r = self.sb.run(["/bin/bash", "-c", f'source "{THEME_SH}"; ab_valid CURSOR_FX "$1"', "x", value])
        return r.returncode == 0

    def names(self):
        r = self.sb.run(["/bin/bash", "-c", f'source "{THEME_SH}"; echo "$AB_CURSOR_FX_NAMES"'])
        return r.stdout.split()

    def test_ab_valid_accepts_exactly_the_listed_names(self):
        names = self.names()
        self.assertIn("embers", names)
        for n in names:
            self.assertTrue(self.valid(n), n)
        # a space-joined list must not let a pair of names, a prefix or an empty value through
        for bad in ("", "embers neon", "ember", "embers|neon", "cyber lightning"):
            self.assertFalse(self.valid(bad), repr(bad))

    def test_first_run_conf_comment_lists_the_same_names(self):
        self.assertEqual(self.sb.afterburn("get", "CURSOR_FX").returncode, 0)
        conf = (self.sb.home / ".config" / "afterburn" / "afterburn.conf").read_text()
        line = next(l for l in conf.splitlines() if l.startswith("#CURSOR_FX="))
        self.assertEqual(line.split("(")[1].split(")")[0].split(), self.names())


class EditionList(unittest.TestCase):
    def setUp(self):
        self.sb = Sandbox()
        self.addCleanup(self.sb.cleanup)

    def run_step6(self, folders):
        """Run the real step 6 text of extras/install.sh against a fake theme root."""
        root = self.sb.root / "theme"
        for name, has_colors in folders.items():
            d = root / ".editions" / name
            d.mkdir(parents=True)
            if has_colors:
                (d / "colors.toml").write_text("mode = \"dark\"\n")
        step = INSTALL_TEXT.split("# 6. Colour editions", 1)[1].split("# Which theme the installer leaves active", 1)[0]
        prelude = (
            'ok() { echo "OK $*"; }; skip() { echo "SKIP $*"; }; ask() { echo "ASK $1"; return 0; }\n'
            f'CHANGED=(); STATE_DIR="$HOME/.local/state/afterburn"; mkdir -p "$STATE_DIR"; HERE="{root}/extras"\n'
            "set -euo pipefail\n# 6. Colour editions")
        return self.sb.run(["/bin/bash", "-c", prelude + step])

    def test_the_folders_are_the_list(self):
        r = self.run_step6({"zeta": True, "alpha": True, "b2": True, "Bad_Name": True, "empty": False, "x-y": True})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("ASK Install colour editions (Alpha, B2, Zeta)?", r.stdout)
        themes = self.sb.home / ".config" / "omarchy" / "themes"
        self.assertEqual(sorted(p.name for p in themes.glob("afterburn-*")), ["afterburn-alpha", "afterburn-b2", "afterburn-zeta"])

    def test_no_folders_means_a_skip(self):
        r = self.run_step6({})
        self.assertIn("SKIP colour editions: no .editions/ folder", r.stdout)

    def test_uninstall_removes_an_edition_with_a_digit_in_its_name(self):
        themes = self.sb.home / ".config" / "omarchy" / "themes"
        (themes / "afterburn-lite2").mkdir()
        (themes / "afterburn-lite2" / "colors.toml").write_text("x")
        self.sb.write_state_text(self.sb.state_dir / "editions", "lite2\n")
        r = self.sb.run(["/bin/bash", str(REPO / "extras" / "uninstall.sh")])
        self.assertIn("edition removed: afterburn-lite2", r.stdout, r.stdout + r.stderr)
        self.assertFalse((themes / "afterburn-lite2").exists())


@unittest.skipUnless(shutil.which("magick") and shutil.which("fc-match"), "build tools not installed")
class BuildScript(unittest.TestCase):
    def test_a_folder_with_no_row_fails_the_build_loudly(self):
        root = pathlib.Path(__import__("tempfile").mkdtemp(prefix="afterburn-build-"))
        self.addCleanup(shutil.rmtree, root, True)
        (root / "tools" / "edition-extras").mkdir(parents=True)
        shutil.copy(REPO / "tools" / "make-editions.sh", root / "tools")
        for name in ("colors.toml", "hyprland.lua", "icons.theme", "backgrounds", "extras"):
            if (REPO / name).exists():
                (root / name).symlink_to(REPO / name)
        for d in (REPO / "tools" / "edition-extras").iterdir():
            (root / "tools" / "edition-extras" / d.name).symlink_to(d)
        (root / "tools" / "edition-extras" / "zzz").mkdir()
        r = subprocess.run(["bash", str(root / "tools" / "make-editions.sh")], capture_output=True, text=True,
                           timeout=120, stdin=subprocess.DEVNULL)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("zzz/ has no row", r.stderr)


if __name__ == "__main__":
    unittest.main()
