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


if __name__ == "__main__":
    unittest.main()
