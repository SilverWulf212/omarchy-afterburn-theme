"""uninstall.sh keeps what is yours: the settings file and every .bashrc line it did not add."""
import unittest

from support import THEME_SH, UNINSTALL, Sandbox

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

    def test_an_earlier_backup_is_never_overwritten(self):
        conf = self.sb.home / ".config" / "afterburn" / "afterburn.conf"
        bak = conf.with_name("afterburn.conf.bak")
        self.sb.write_state_text(bak, "MINE=1\n")                 # a .bak the user made
        self.sb.write_state_text(conf, "ZIP=1\n")
        r1 = self.uninstall()
        self.sb.write_state_text(conf, "ZIP=2\n")                 # reinstall, new settings, uninstall again
        r2 = self.uninstall()
        texts = sorted(p.read_text() for p in conf.parent.glob("afterburn.conf.bak*"))
        self.assertEqual(texts, ["MINE=1\n", "ZIP=1\n", "ZIP=2\n"])
        self.assertEqual(bak.read_text(), "MINE=1\n")
        self.assertIn("afterburn.conf.bak.1", r1.stdout)
        self.assertIn("afterburn.conf.bak.2", r2.stdout)

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


class UninstallKeepsYourLaterChoices(unittest.TestCase):
    """The installer's terminal and font are put back only while they are still the ones it set."""

    def setUp(self):
        self.sb = Sandbox()
        self.addCleanup(self.sb.cleanup)
        self.sb.write_state_text(self.sb.state_dir / "prev-terminal", "Alacritty.desktop\n")
        self.sb.write_state_text(self.sb.state_dir / "prev-font", "Cascadia Mono\n")

    def uninstall(self, terminal, font):
        self.sb.write_state_text(self.sb.home / ".config" / "xdg-terminals.list",
                                 f"# comment\n{terminal}\n")
        self.sb.write_state_text(self.sb.root / "font", font + "\n")
        r = self.sb.run(["/bin/bash", str(UNINSTALL)])
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        return r

    def test_terminal_and_font_the_installer_set_are_restored(self):
        r = self.uninstall("com.mitchellh.ghostty.desktop", "JetBrainsMono Nerd Font")
        calls = self.sb.call_log()
        self.assertIn("omarchy default terminal alacritty", calls)
        self.assertIn("omarchy font set Cascadia Mono", calls)
        self.assertIn("default terminal restored to alacritty", r.stdout)

    def test_a_terminal_chosen_after_the_install_is_left_alone(self):
        r = self.uninstall("kitty.desktop", "JetBrainsMono Nerd Font")
        self.assertFalse([c for c in self.sb.call_log() if "default terminal" in c], self.sb.call_log())
        self.assertIn("default terminal changed since install; left as is", r.stdout)

    def test_a_font_chosen_after_the_install_is_left_alone(self):
        r = self.uninstall("com.mitchellh.ghostty.desktop", "Fira Code")
        self.assertFalse([c for c in self.sb.call_log() if "font set" in c], self.sb.call_log())
        self.assertIn("font changed since install; left as is", r.stdout)


if __name__ == "__main__":
    unittest.main()
