"""Afterburn Lite, the light edition: a readable palette, a runtime that knows ink from glow, and the
built theme folder. Everything runs against the checkout with a throwaway HOME and stub commands."""
import pathlib
import re
import subprocess
import unittest

from support import REPO, Sandbox

SRC = REPO / "tools" / "edition-extras" / "lite"
BUILT = REPO / ".editions" / "lite"
THEME_SH = REPO / "extras" / "afterburn-theme.sh"
HOOK = REPO / "extras" / "afterburn-theme-set-hook"

TEXT_KEYS = ("accent foreground light_foreground red yellow green cyan blue magenta "
             "bright_red bright_yellow bright_green bright_cyan bright_blue bright_magenta").split()


def toml(path):
    return dict(re.findall(r'^([a-z_]+)\s*=\s*"([^"]*)"', pathlib.Path(path).read_text(), re.M))


def luminance(hexcolour):
    h = hexcolour.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    c = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def contrast(a, b):
    hi, lo = sorted((luminance(a), luminance(b)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


class Palette(unittest.TestCase):
    def setUp(self):
        self.c = toml(SRC / "colors.toml")

    def test_it_is_a_light_palette(self):
        self.assertEqual(self.c["mode"], "light")
        self.assertGreater(luminance(self.c["background"]), 0.8)

    def test_every_text_colour_reads_on_the_paper(self):
        for key in TEXT_KEYS:
            with self.subTest(key=key):
                self.assertGreaterEqual(contrast(self.c[key], self.c["background"]), 4.5)

    def test_body_text_reads_on_a_selection(self):
        self.assertGreaterEqual(contrast(self.c["foreground"], self.c["selection"]), 7)

    def test_the_runtime_keys_are_there(self):
        stops = re.findall(r"rgba\(([0-9a-f]{6})[0-9a-f]{2}\)", self.c["hyprland_active_border"])
        self.assertEqual(len(stops), 3)
        for key in ("brown", "dark_foreground", "afterburn_cool", "hyprland_inactive_border"):
            self.assertIn(key, self.c)


class Runtime(unittest.TestCase):
    def setUp(self):
        self.sb = Sandbox()
        self.addCleanup(self.sb.cleanup)
        lite = self.sb.home / ".config/omarchy/themes/afterburn-lite"
        lite.mkdir(parents=True)
        (lite / "colors.toml").write_text((SRC / "colors.toml").read_text())
        (lite / "edition.conf").write_text((SRC / "edition.conf").read_text())

    def palette(self, theme):
        r = self.sb.run(["/bin/bash", "-c",
                         f'. "{THEME_SH}"; ab_load_palette {theme}; '
                         'echo "$AB_MODE $AB_ACCENT $AB_HOTWHITE $AB_HOTGLOW $AB_SHADOW_INACTIVE"'])
        self.assertEqual(r.returncode, 0, r.stderr)
        return r.stdout.split()

    def test_base_theme_is_untouched(self):
        self.assertEqual(self.palette("afterburn"), ["dark", "f59145", "fff1e0", "ffb37a", "00000066"])
        r = self.sb.run(["/bin/bash", "-c",
                         f'. "{THEME_SH}"; ab_load_palette afterburn; ab_recolor_glow "{REPO}/extras/hyprland-glow.lua"'])
        self.assertEqual(r.stdout, (REPO / "extras/hyprland-glow.lua").read_text())

    def test_lite_hot_level_is_ink_not_white(self):
        mode, accent, hotwhite, hotglow, shadow = self.palette("afterburn-lite")
        self.assertEqual(mode, "light")
        paper = toml(SRC / "colors.toml")["background"]
        # A hot stop lighter than the paper would vanish: it has to stay clearly darker.
        self.assertGreaterEqual(contrast("#" + hotwhite, paper), 4.5)
        self.assertGreaterEqual(contrast("#" + hotglow, paper), 3)
        self.assertNotEqual(shadow, "00000066")

    def test_lite_glow_file_has_no_black_shadow(self):
        r = self.sb.run(["/bin/bash", "-c",
                         f'. "{THEME_SH}"; ab_load_palette afterburn-lite; ab_recolor_glow "{REPO}/extras/hyprland-glow.lua"'])
        self.assertNotIn("00000066", r.stdout)
        self.assertNotIn("f59145", r.stdout)
        self.assertIn("c2410c", r.stdout)

    def test_edition_knobs_pass_the_runtime_checks(self):
        r = self.sb.run(["/bin/bash", "-c",
                         f'. "{THEME_SH}"; for k in $AB_EDITION_KEYS; do ab_effective $k afterburn-lite; echo "$k=$AB_VAL:$AB_SRC"; done'])
        got = dict(line.split("=", 1) for line in r.stdout.split())
        self.assertEqual(got, {"CURSOR_FX": "embers:edition", "ROTATE": "off:edition", "DIM": "0.03:edition",
                               "GLOW_RANGE": "10:edition", "EMBER_STYLE": "drift:edition"})

    def effective(self, conf, theme="afterburn-lite"):
        path = self.sb.home / ".config/afterburn/afterburn.conf"
        self.sb.write_state_text(path, conf)
        r = self.sb.run(["/bin/bash", "-c",
                         f'. "{THEME_SH}"; for k in $AB_EDITION_KEYS; do ab_effective $k {theme}; echo "$k=$AB_VAL:$AB_SRC"; done'])
        self.assertEqual(r.returncode, 0, r.stderr)
        return dict(line.split("=", 1) for line in r.stdout.split()), r.stderr.replace(str(path), "CONF")

    def test_your_conf_against_the_edition_follows_the_rules(self):
        # Last line wins, leading spaces and one pair of quotes are fine, a commented line is not a value, a
        # first-run default line follows the edition, and a bad or empty value falls back to the edition.
        got, err = self.effective(
            "ROTATE=slow          # off|slow|medium|fast  (border gradient turn: 60s|20s|8s per turn)\n"
            "DIM=0.5\n   DIM=\"0.2\"   # indented, quoted, last\n#CURSOR_FX=cyber\nCURSOR_FX='neon'  # set by you\n"
            "GLOW_RANGE=20\nGLOW_RANGE=99\nEMBER_STYLE=\nEMBER_STYLE=spark")          # no newline at the end
        self.assertEqual(got, {"ROTATE": "off:edition", "DIM": "0.2:conf", "CURSOR_FX": "neon:conf",
                               "GLOW_RANGE": "10:edition", "EMBER_STYLE": "spark:conf"})
        self.assertEqual(err, "afterburn: ignoring GLOW_RANGE='99' in CONF (not an allowed value)\n")

    def test_a_first_run_default_line_is_judged_on_unindented_lines_only(self):
        conf = ("  ROTATE=fast\nDIM=0.08             # dim_inactive strength, 0 = off\n DIM=0.5\n"
                "EMBER_STYLE=\nCURSOR_FX=bogus\n")
        got, err = self.effective(conf)
        self.assertEqual(got, {"ROTATE": "fast:conf", "DIM": "0.03:edition", "CURSOR_FX": "embers:edition",
                               "GLOW_RANGE": "10:edition", "EMBER_STYLE": "drift:edition"})
        self.assertEqual(err, "afterburn: ignoring CURSOR_FX='bogus' in CONF (not an allowed value)\n")
        got, _ = self.effective(conf, theme="afterburn")       # the base theme has no edition.conf
        self.assertEqual(got, {"ROTATE": "fast:conf", "DIM": "0.08:default", "CURSOR_FX": "embers:default",
                               "GLOW_RANGE": "14:default", "EMBER_STYLE": "rise:default"})


class CursorFollowsTheBackground(unittest.TestCase):
    """cursor-fx reads the terminal background only when it switches effects. Base and Lite both use
    embers, so moving between them must switch anyway, or Lite keeps the dark themes' glow."""

    def setUp(self):
        self.sb = Sandbox()
        self.addCleanup(self.sb.cleanup)
        lite = self.sb.home / ".config/omarchy/themes/afterburn-lite"
        lite.mkdir(parents=True)
        (lite / "colors.toml").write_text((SRC / "colors.toml").read_text())
        (lite / "edition.conf").write_text((SRC / "edition.conf").read_text())
        ghostty = self.sb.home / ".config/ghostty"
        ghostty.mkdir(parents=True)
        (ghostty / "config").write_text("config-file = cursor-effects/embers.conf\n")

    def hook(self, theme):
        self.sb.write_state_text(self.sb.home / ".local/state/omarchy/current/theme.name", theme)
        before = len(self.sb.calls.read_text().splitlines())
        r = self.sb.run(["/bin/bash", str(HOOK), theme])
        self.assertEqual(r.returncode, 0, r.stderr)
        return [l for l in self.sb.calls.read_text().splitlines()[before:] if l.startswith("cursor-fx ")]

    def test_same_effect_same_mode_does_not_switch(self):
        self.assertEqual(self.hook("afterburn"), [])

    def test_dark_to_light_and_back_switches(self):
        self.hook("afterburn")
        self.assertEqual(self.hook("afterburn-lite"), ["cursor-fx embers"])
        self.assertEqual(self.hook("afterburn-lite"), [])
        self.assertEqual(self.hook("afterburn"), ["cursor-fx embers"])


class BuiltEdition(unittest.TestCase):
    def test_the_folder_is_a_complete_light_theme(self):
        c = toml(BUILT / "colors.toml")
        self.assertEqual(c["mode"], "light")
        self.assertEqual((BUILT / "icons.theme").read_text().strip(), "Yaru")
        lua = (BUILT / "hyprland.lua").read_text()
        self.assertNotIn("00000066", lua)
        self.assertNotIn("f59145", lua)
        self.assertIn("range = 10", lua)
        for name in ("unlock.png", "preview.png", "preview-unlock.png", "edition.conf"):
            self.assertTrue((BUILT / name).is_file(), name)

    def test_wallpapers_are_bright_and_have_heat_variants(self):
        stills = sorted(p.name for p in (BUILT / "backgrounds").glob("*.jpg"))
        self.assertEqual(stills, ["1-horizon.jpg", "2-prompt.jpg", "3-circuit.jpg", "4-nozzle.jpg", "5-flow.jpg",
                                  "6-ember.jpg", "7-sunprint.jpg", "8-heat-shield.jpg"])
        for level in ("cool", "hot"):
            self.assertEqual(sorted(p.name for p in (BUILT / "heat-wallpapers" / level).glob("*.jpg")), stills)
        self.assertEqual([p.name for p in (BUILT / "backgrounds").glob("*.mp4")], ["live-heat-shield.mp4"])
        means = subprocess.check_output(
            ["magick", "-define", "jpeg:size=480x270", *(str(BUILT / "backgrounds" / n) for n in stills),
             "-colorspace", "Gray", "-format", "%[fx:mean]\n", "info:"], text=True).split()
        self.assertEqual(len(means), len(stills))
        for name, mean in zip(stills, means):
            self.assertGreater(float(mean), 0.7, f"{name} is not a light wallpaper")

    def test_light_art_stays_out_of_the_dark_picker(self):
        self.assertEqual(list((REPO / "backgrounds").glob("lite-*")), [])

    def test_the_installer_will_find_it(self):
        # install.sh lists the folders under .editions/ that hold a colors.toml (see test_names.py)
        self.assertTrue((BUILT / "colors.toml").is_file())


if __name__ == "__main__":
    unittest.main()
