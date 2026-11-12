"""uninstall.sh keeps what is yours: the settings file and every .bashrc line it did not add."""
import shutil
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


class UninstallRestoresExactlyWhatInstallChanged(unittest.TestCase):
    def setUp(self):
        self.sb = Sandbox()
        self.addCleanup(self.sb.cleanup)
        self.list = self.sb.home / ".config" / "xdg-terminals.list"

    def uninstall(self, **extra):
        return self.sb.run(["/bin/bash", str(UNINSTALL)], **extra)

    def test_a_fresh_user_gets_the_system_default_back(self):
        # No list before the install; `omarchy default terminal ghostty` creates one (the stub does not).
        self.assertEqual(self.sb.install().returncode, 0)
        self.sb.write_state_text(self.list, "# written by omarchy\ncom.mitchellh.ghostty.desktop\n")
        r = self.uninstall()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertFalse(self.list.exists())
        self.assertIn("default terminal", r.stdout)
        self.assertFalse([c for c in self.sb.call_log() if "default terminal" in c and "ghostty" not in c])

    def test_reinstall_after_uninstall_records_no_list_again(self):
        self.sb.install()
        self.sb.write_state_text(self.list, "com.mitchellh.ghostty.desktop\n")
        self.uninstall()
        self.sb.install()
        self.assertEqual((self.sb.state_dir / "prev-terminal").read_text().strip(), "none")

    def test_a_terminal_chosen_after_a_fresh_install_is_left_alone(self):
        self.sb.write_state_text(self.sb.state_dir / "prev-terminal", "none\n")
        self.sb.write_state_text(self.list, "kitty.desktop\n")
        r = self.uninstall()
        self.assertEqual(self.list.read_text(), "kitty.desktop\n")
        self.assertIn("default terminal changed since install; left as is", r.stdout)

    def test_a_list_with_your_own_fallback_lines_is_kept(self):
        self.sb.write_state_text(self.sb.state_dir / "prev-terminal", "none\n")
        text = "com.mitchellh.ghostty.desktop\nfoot.desktop\n"
        self.sb.write_state_text(self.list, text)
        r = self.uninstall()
        self.assertEqual(self.list.read_text(), text)
        self.assertIn("terminal list has your own lines; left as is", r.stdout)

    def test_a_list_of_ghostty_and_comments_only_is_removed(self):
        self.sb.write_state_text(self.sb.state_dir / "prev-terminal", "none\n")
        self.sb.write_state_text(self.list, "# mine\n\ncom.mitchellh.ghostty.desktop\n")
        self.uninstall()
        self.assertFalse(self.list.exists())

    def failing_writes(self):
        """mktemp hands out a dangling link, so writing the temp file fails (a link to /dev/full would read as endless zeros
        if a regression moved it over the user's file)."""
        stub = self.sb.bin / "mktemp"
        stub.unlink()
        stub.write_text(f'''#!/bin/bash
f=$({shutil.which("mktemp")} "$@") || exit 1
rm -f "$f"; ln -s /nonexistent/dir/x "$f"; echo "$f"
''')
        stub.chmod(0o755)

    def test_a_failed_starship_write_keeps_the_file_and_says_so(self):
        starship = self.sb.home / ".config" / "starship.toml"
        text = '[character]\nerror_symbol = "[❯](bold red)"\n'
        self.sb.write_state_text(starship, text)
        self.sb.write_state_text(self.sb.state_dir / "starship-error-symbol", 'error_symbol = "[x](red)"\n')
        self.failing_writes()
        r = self.uninstall()
        self.assertEqual(starship.read_text(), text)
        self.assertIn("not restored", r.stdout)
        self.assertNotIn("✓ starship", r.stdout)
        self.assertNotEqual(r.returncode, 0)
        self.assertTrue((self.sb.state_dir / "starship-error-symbol").exists())
        self.assertEqual([p.name for p in starship.parent.glob(".starship.*")], [])

    def test_a_failed_bashrc_write_keeps_the_file_and_says_so(self):
        rc = self.sb.home / ".bashrc"
        text = f"alias a=b\n{LINE}\n"
        rc.write_text(text)
        self.failing_writes()
        r = self.uninstall()
        self.assertEqual(rc.read_text(), text)
        self.assertIn("not restored", r.stdout)
        self.assertNotIn("✓ ~/.bashrc", r.stdout)
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual([p.name for p in rc.parent.glob(".bashrc.*")], [])

    def test_preview_backups_survive_for_the_manual_undo(self):
        keep = self.sb.state_dir / "preview-backups" / "hyprland.lua.bak"
        self.sb.write_state_text(keep, "mine\n")
        self.sb.write_state_text(self.sb.state_dir / "editions", "")
        self.assertEqual(self.uninstall().returncode, 0)
        self.assertEqual(keep.read_text(), "mine\n")
        self.assertFalse((self.sb.state_dir / "editions").exists())

    def test_the_watcher_stops_before_the_cursor_effect_is_restored(self):
        self.sb.write_state_text(self.sb.state_dir / "prev-cursor-fx", "ember\n")
        r = self.uninstall()     # no unit file on disk: the stop does not depend on it
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        calls = self.sb.call_log()
        stop = calls.index("systemctl --user disable --now afterburn-watch.service")
        self.assertLess(stop, calls.index("cursor-fx ember"))


if __name__ == "__main__":
    unittest.main()
