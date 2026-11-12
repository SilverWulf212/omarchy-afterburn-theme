"""Omarchy owns a fixed state path; Afterburn and Ghostty honour their XDG paths."""
import unittest

from support import REPO, Sandbox

HOOK = REPO / "extras/afterburn-theme-set-hook"


class GhosttyPaths(unittest.TestCase):
    def test_cli_and_hook_read_fallback_and_prefer_config_in_both_config_homes(self):
        for custom in (False, True):
            for fallback in (True, False):
                for hook in (False, True):
                    with self.subTest(custom=custom, fallback=fallback, hook=hook):
                        sb = Sandbox()
                        self.addCleanup(sb.cleanup)
                        config = sb.root / "xdg-config" if custom else sb.home / ".config"
                        ghostty = config / "ghostty"
                        ghostty.mkdir(parents=True, exist_ok=True)
                        (ghostty / "config.ghostty").write_text(
                            f"config-file = cursor-effects/{'lightning' if fallback else 'cyber'}.conf\n")
                        if not fallback:
                            (ghostty / "config").write_text("config-file = cursor-effects/lightning.conf\n")
                        env = {"XDG_CONFIG_HOME": str(config)} if custom else {}
                        if hook:
                            sb.use_stubs(["afterburn"])
                            r = sb.run(["/bin/bash", str(HOOK), "afterburn"], **env)
                            self.assertEqual(r.returncode, 0, r.stderr)
                            self.assertEqual((sb.state_dir / "prev-cursor-fx").read_text().strip(), "lightning")
                        else:
                            r = sb.afterburn("status", **env)
                            self.assertEqual(r.returncode, 0, r.stderr)
                            self.assertIn("cursor:   lightning", r.stdout)


class OmarchyStatePaths(unittest.TestCase):
    def setUp(self):
        self.sb = Sandbox()
        self.addCleanup(self.sb.cleanup)
        self.current = self.sb.home / ".local/state/omarchy/current/theme"
        self.current.mkdir(parents=True)
        self.sb.write_state_text(self.current.with_suffix(".name"), "afterburn-custom\n")
        (self.current / "colors.toml").write_text(
            'hyprland_active_border = "rgba(112233ff) rgba(445566ff) rgba(778899ff)"\n')
        (self.current / "edition.conf").write_text("GLOW_RANGE=18\nCURSOR_FX=neon\n")
        self.state = self.sb.root / "xdg-state"
        self.env = {"XDG_STATE_HOME": str(self.state)}
        self.sb.write_state_text(self.state / "omarchy/current/theme.name", "other\n")

    def test_cli_uses_fixed_omarchy_state_and_staged_palette_and_edition(self):
        r = self.sb.afterburn("apply", **self.env)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertTrue((self.current / "hyprland.lua").exists(), r.stdout)
        lua = (self.current / "hyprland.lua").read_text()
        self.assertIn("112233", lua)
        self.assertIn("range = 18", lua)
        self.assertIn("EMBER=445566", (self.state / "afterburn/palette.env").read_text())
        self.assertFalse(self.sb.state_dir.exists())

    def test_hook_uses_fixed_omarchy_state_for_guard_and_no_cli_fallback(self):
        r = self.sb.run(["/bin/bash", str(HOOK), "afterburn-custom"], **self.env)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue((self.current / "hyprland.lua").exists(), self.sb.call_log())
        self.assertIn("112233", (self.current / "hyprland.lua").read_text())
        self.assertIn("cursor-fx neon", self.sb.call_log())
        self.assertIn("EMBER=445566", (self.state / "afterburn/palette.env").read_text())
        self.assertTrue((self.state / "afterburn/cursor-fx-set").exists())
        self.assertFalse(self.sb.state_dir.exists())

    def test_watcher_reads_fixed_omarchy_theme_name_with_custom_state_home(self):
        self.sb.use_stubs(["afterburn"])
        r = self.sb.watch_func("fullscreen_event 'fullscreen>>1'", **self.env)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.sb.call_log(), ["afterburn quiet on"])


if __name__ == "__main__":
    unittest.main()
