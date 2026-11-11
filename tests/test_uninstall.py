"""uninstall.sh keeps what is yours: the settings file and every .bashrc line it did not add."""
import unittest

from support import REPO, UNINSTALL, Sandbox

THEME_SH = REPO / "extras" / "afterburn-theme.sh"
# The line every release since the subtle pack has written. Pinned, so a change here is a decision.
LINE = ('[[ -f "$HOME/.config/omarchy/themes/afterburn/extras/afterburn-fail.bash" ]] && '
        'source "$HOME/.config/omarchy/themes/afterburn/extras/afterburn-fail.bash"  # afterburn')


class UninstallKeepsYourThings(unittest.TestCase):
    def setUp(self):
        self.sb = Sandbox()
        self.addCleanup(self.sb.cleanup)

    def uninstall(self):
        r = self.sb.run(["/bin/bash", str(UNINSTALL)])
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        return r

    def test_the_installer_line_is_the_pinned_one(self):
        r = self.sb.run(["/bin/bash", "-c", f'source "{THEME_SH}"; printf %s "$AB_BASHRC_LINE"'])
        self.assertEqual(r.stdout, LINE)

    def test_settings_are_kept_as_a_bak_file(self):
        conf = self.sb.home / ".config" / "afterburn" / "afterburn.conf"
        self.sb.write_state_text(conf, "HEAT_SOURCE=weather\nZIP=90210\n")
        r = self.uninstall()
        self.assertFalse(conf.exists())
        self.assertEqual(conf.with_name("afterburn.conf.bak").read_text(), "HEAT_SOURCE=weather\nZIP=90210\n")
        self.assertIn("afterburn.conf.bak", r.stdout)

    def test_no_conf_means_no_bak(self):
        self.uninstall()
        self.assertFalse((self.sb.home / ".config" / "afterburn").exists())

    def test_bashrc_loses_only_the_installer_line(self):
        mine = 'export EDITOR=nvim  # afterburn'
        rc = self.sb.home / ".bashrc"
        rc.write_text(f"alias ll='ls -l'\n{mine}\n{LINE}\n# afterburn\n")
        self.uninstall()
        self.assertEqual(rc.read_text(), f"alias ll='ls -l'\n{mine}\n# afterburn\n")

    def test_bashrc_with_only_foreign_marker_lines_is_untouched(self):
        rc = self.sb.home / ".bashrc"
        rc.write_text("export A=1  # afterburn\n")
        r = self.uninstall()
        self.assertEqual(rc.read_text(), "export A=1  # afterburn\n")
        self.assertNotIn("~/.bashrc line removed", r.stdout)


if __name__ == "__main__":
    unittest.main()
