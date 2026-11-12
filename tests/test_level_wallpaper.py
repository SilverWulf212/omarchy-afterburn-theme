"""`afterburn level` swaps the heat wallpaper even while quiet or saver is on; only the glow change waits."""
import unittest

from support import REPO, Sandbox

BG_SET = '#!/bin/bash\necho "omarchy-theme-bg-set $*" >> "$SB/calls.log"\n'


class LevelWallpaperInModes(unittest.TestCase):
    def setUp(self):
        self.sb = Sandbox()
        self.addCleanup(self.sb.cleanup)
        (self.sb.bin / "omarchy-theme-bg-set").write_text(BG_SET)
        (self.sb.bin / "omarchy-theme-bg-set").chmod(0o755)
        cur = self.sb.home / ".local/state/omarchy/current"
        self.name = sorted(p.name for p in (REPO / "extras/heat-wallpapers/cool").glob("*.jpg"))[0]
        (cur / "theme/backgrounds").mkdir(parents=True)
        (cur / "theme/backgrounds" / self.name).write_text("normal wallpaper")
        (cur / "background").symlink_to(cur / "theme/backgrounds" / self.name)

    def level_in(self, mode):
        self.sb.write_state_text(self.sb.state_dir / mode, "on\n")
        r = self.sb.afterburn("level", "cool")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        calls = self.sb.call_log()
        want = f"omarchy-theme-bg-set {self.sb.home}/.config/omarchy/themes/afterburn/extras/heat-wallpapers/cool/{self.name}"
        self.assertIn(want, calls)
        self.assertFalse([c for c in calls if c.startswith("hyprctl eval")], calls)

    def test_saver_on_still_swaps_wallpaper_but_not_glow(self):
        self.level_in("saver")

    def test_quiet_on_still_swaps_wallpaper_but_not_glow(self):
        self.level_in("quiet")

    def test_personal_wallpaper_with_the_same_basename_is_left_alone(self):
        personal = self.sb.home / "Pictures" / self.name
        self.sb.write_state_text(personal, "personal wallpaper")
        link = self.sb.home / ".local/state/omarchy/current/background"
        link.unlink()
        link.symlink_to(personal)
        r = self.sb.afterburn("level", "hot")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertFalse([c for c in self.sb.call_log() if c.startswith("omarchy-theme-bg-set ")])
        self.assertEqual(link.resolve(), personal)
        self.assertEqual(personal.read_text(), "personal wallpaper")

    def test_all_theme_wallpaper_directories_can_swap_through_symlinks(self):
        current = self.sb.home / ".local/state/omarchy/current"
        theme = self.sb.home / ".config/omarchy/themes/afterburn"
        dirs = {"normal": current / "theme/backgrounds",
                "cool": theme / "extras/heat-wallpapers/cool", "hot": theme / "extras/heat-wallpapers/hot"}
        alias = self.sb.root / "wallpapers"
        for source, target in (("normal", "hot"), ("cool", "normal"), ("hot", "cool")):
            with self.subTest(source=source, target=target):
                if alias.is_symlink():
                    alias.unlink()
                alias.symlink_to(dirs[source], target_is_directory=True)
                (current / "background").unlink()
                (current / "background").symlink_to(alias / self.name)
                self.sb.calls.write_text("")
                r = self.sb.afterburn("level", target)
                self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
                self.assertIn(f"omarchy-theme-bg-set {dirs[target] / self.name}", self.sb.call_log())


if __name__ == "__main__":
    unittest.main()
