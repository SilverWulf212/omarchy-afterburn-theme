"""Small installer-side fixes: conf_set saves a key the conf lacks, the glow copy stays in step, locate ignores the locale."""
import re
import shutil
import subprocess
import unittest

from support import INSTALL, REPO, Sandbox


class ConfSetTests(unittest.TestCase):
    def setUp(self):
        self.sb = Sandbox()
        self.addCleanup(self.sb.cleanup)

    def conf_set(self, conf, key, value):
        # install.sh is an interactive script, so run just its conf_set function against a sandbox conf.
        m = re.search(r"^conf_set\(\) \{.*?^\}", INSTALL.read_text(), re.S | re.M)
        self.assertIsNotNone(m, "conf_set not found in install.sh")
        return self.sb.run(["/bin/bash", "-c", f'CONF="{conf}"; {m.group(0)}; conf_set {key} {value}'])

    def test_a_conf_without_the_key_gets_it_appended(self):
        conf = self.sb.home / "afterburn.conf"
        conf.write_text("ZIP=90210\n")
        r = self.conf_set(conf, "HEAT_SOURCE", "pressure")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(conf.read_text(), "ZIP=90210\nHEAT_SOURCE=pressure\n")

    def test_a_conf_without_a_final_newline_does_not_glue_the_line(self):
        conf = self.sb.home / "afterburn.conf"
        conf.write_text("ZIP=90210")
        self.conf_set(conf, "HEAT_SOURCE", "time")
        self.assertEqual(conf.read_text(), "ZIP=90210\nHEAT_SOURCE=time\n")

    def test_an_existing_line_is_rewritten_with_its_comment_kept(self):
        conf = self.sb.home / "afterburn.conf"
        conf.write_text("HEAT_SOURCE=time  # default\nZIP=1\n")
        self.conf_set(conf, "HEAT_SOURCE", "off")
        self.assertEqual(conf.read_text(), "HEAT_SOURCE=off  # default\nZIP=1\n")


class GlowCopyTests(unittest.TestCase):
    def test_hyprland_glow_lua_matches_hyprland_lua_after_the_header(self):
        a = (REPO / "hyprland.lua").read_text().split("\n", 1)[1]
        b = (REPO / "extras" / "hyprland-glow.lua").read_text().split("\n", 1)[1]
        self.assertEqual(a, b)


class LocateLocaleTests(unittest.TestCase):
    def test_locate_formats_lat_lon_with_a_dot_under_a_comma_locale(self):
        sb = Sandbox()
        self.addCleanup(sb.cleanup)
        # No comma-decimal locale is installed system-wide, so compile de_DE into the sandbox and point LOCPATH at it.
        loc = sb.root / "locales"
        loc.mkdir()
        built = subprocess.run(["localedef", "-i", "de_DE", "-f", "UTF-8", str(loc / "de_DE.UTF-8")],
                               capture_output=True, text=True) if shutil.which("localedef") else None
        if built is None or not (loc / "de_DE.UTF-8" / "LC_NUMERIC").exists():
            self.skipTest("cannot build a de_DE locale here")
        # The ZIP lookup is faked: curl is not one of the sandbox tools.
        curl = sb.bin / "curl"
        curl.write_text('#!/bin/bash\necho \'{"places":[{"latitude":"34.0901","longitude":"-118.4065"}]}\'\n')
        curl.chmod(0o755)
        r = sb.afterburn("locate", "90210", LOCPATH=str(loc), LC_ALL="de_DE.UTF-8")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("LAT 34.0901, LON -118.4065", r.stdout)


if __name__ == "__main__":
    unittest.main()
