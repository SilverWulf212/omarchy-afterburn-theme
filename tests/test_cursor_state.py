"""Quiet and saver each own one thing: quiet holds the cursor effect off (and saves it in cursor-pre-quiet), saver
only stops Ghostty animating shaders (one marked line in its config). They overlap in any order, and neither may
leave the effect off. A subtle-by-afterburn record left by an older saver is undone once."""
import unittest

from support import REPO, Sandbox

MARK = "# afterburn battery saver: shaders draw only when the terminal changes (removed when you plug in)"
STILL = "custom-shader-animation = false"   # no comment after the value: Ghostty rejects the whole line

HOOK = REPO / "extras" / "afterburn-theme-set-hook"

# cursor-fx as far as these scripts can see it: the effect lives in Ghostty's config, `subtle` is a flag.
CURSOR_FX = r'''#!/bin/bash
echo "cursor-fx $*" >> "$SB/calls.log"
cfg="$HOME/.config/ghostty/config"
[[ -e $SB/cfx-fails && ${1:-} != subtle ]] && exit 1
case ${1:-} in
  subtle)
    case ${2:-} in
      on|off) echo "${2}" > "$SB/subtle" ;;
      *) echo "Subtle version: $(cat "$SB/subtle" 2>/dev/null || echo off) (cursor-fx subtle on|off)" ;;
    esac ;;
  off) : > "$cfg" ;;
  *) echo "config-file = cursor-effects/$1.conf" > "$cfg" ;;
esac
'''


class CursorBookkeeping(unittest.TestCase):
    def setUp(self):
        self.sb = Sandbox()
        self.addCleanup(self.sb.cleanup)
        (self.sb.bin / "cursor-fx").write_text(CURSOR_FX)
        (self.sb.bin / "cursor-fx").chmod(0o755)
        (self.sb.home / ".local/state/omarchy/current/theme").mkdir(parents=True)
        self.ghostty = self.sb.home / ".config/ghostty/config"
        self.ghostty.parent.mkdir(parents=True, exist_ok=True)
        self.pre = self.sb.state_dir / "cursor-pre-quiet"
        self.start("lightning")

    def start(self, effect):
        self.ghostty.write_text(f"config-file = cursor-effects/{effect}.conf\n")

    def effect(self):
        text = self.ghostty.read_text()
        return text.split("cursor-effects/")[1].split(".")[0] if "cursor-effects/" in text else "off"

    def subtle(self):
        f = self.sb.root / "subtle"
        return f.read_text().strip() if f.exists() else "off"

    def ab(self, *args):
        r = self.sb.afterburn(*args)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_quiet_alone_saves_the_effect_and_puts_it_back(self):
        self.ab("quiet", "on")
        self.assertEqual((self.effect(), self.pre.read_text().strip()), ("off", "lightning"))
        self.ab("quiet", "off")
        self.assertEqual((self.effect(), self.pre.exists()), ("lightning", False))

    def still(self):
        return self.ghostty.read_text().splitlines().count(STILL)

    def test_saver_stops_animation_and_keeps_the_effect(self):
        self.ghostty.write_text("font-size = 9\ncustom-shader = shaders/mine.glsl\nconfig-file = cursor-effects/lightning.conf\n")
        self.ab("saver", "on")
        self.assertEqual((self.effect(), self.still(), self.pre.exists()), ("lightning", 1, False))
        self.assertTrue(self.ghostty.read_text().endswith(MARK + "\n" + STILL + "\n"))   # last, so it wins
        self.ab("saver", "on")                                                # again: still one line, no reload
        self.assertEqual(self.still(), 1)
        self.assertEqual(self.sb.call_log().count("pkill -USR2 -x ghostty"), 1)
        self.ab("saver", "off")
        self.assertEqual(self.ghostty.read_text(),
                         "font-size = 9\ncustom-shader = shaders/mine.glsl\nconfig-file = cursor-effects/lightning.conf\n")
        self.assertEqual(self.sb.call_log().count("pkill -USR2 -x ghostty"), 2)

    def test_the_one_line_form_an_earlier_version_wrote_is_cleaned_up(self):
        old = STILL + "  # afterburn battery saver (removed when you plug in)"
        self.ghostty.write_text("font-size = 9\n" + old + "\n")
        self.ab("apply")                                       # saver off
        self.assertEqual(self.ghostty.read_text(), "font-size = 9\n")
        self.ghostty.write_text("font-size = 9\n" + old + "\n")
        self.ab("saver", "on")
        self.assertEqual(self.ghostty.read_text(), "font-size = 9\n" + MARK + "\n" + STILL + "\n")

    def test_your_own_animation_line_is_never_touched(self):
        self.ghostty.write_text("font-size = 9\n" + STILL + "\n")
        self.ab("saver", "on")
        self.ab("saver", "off")
        self.assertEqual(self.ghostty.read_text(), "font-size = 9\n" + STILL + "\n")

    def test_saver_keeps_a_symlinked_config_a_symlink(self):
        real = self.sb.home / "dotfiles-ghostty"
        real.write_text("font-size = 9\n")
        self.ghostty.unlink()
        self.ghostty.symlink_to(real)
        self.ab("saver", "on")
        self.ab("saver", "off")
        self.assertTrue(self.ghostty.is_symlink())
        self.assertEqual(real.read_text(), "font-size = 9\n")

    def test_leaving_afterburn_drops_the_saver_line(self):
        self.hook("afterburn")
        self.ab("saver", "on")
        self.assertEqual(self.still(), 1)
        self.hook("nord")
        self.assertEqual(self.still(), 0)

    def test_saver_never_touches_your_subtle_setting(self):
        for subtle in ("off", "mixed", "on"):
            with self.subTest(subtle=subtle):
                self.sb.write_state_text(self.sb.state_dir / "saver", "off\n")
                self.sb.write_state_text(self.sb.root / "subtle", subtle + "\n")
                self.sb.calls.write_text("")
                self.ab("saver", "on")
                self.ab("saver", "off")
                self.assertEqual(self.subtle(), subtle)
                self.assertFalse([c for c in self.sb.call_log() if c.startswith("cursor-fx subtle")])

    def test_a_subtle_an_older_saver_turned_on_is_turned_off_once(self):
        self.sb.write_state_text(self.sb.root / "subtle", "on\n")
        self.sb.write_state_text(self.sb.state_dir / "subtle-by-afterburn", "")
        self.ab("apply")
        self.assertEqual(self.subtle(), "off")
        self.assertFalse((self.sb.state_dir / "subtle-by-afterburn").exists())

    def test_quiet_ending_while_saver_is_on_brings_the_effect_back(self):  # spec bug 1
        self.ab("saver", "on")
        self.ab("quiet", "on")
        self.assertEqual((self.effect(), self.pre.read_text().strip()), ("off", "lightning"))
        self.ab("quiet", "off")
        self.assertEqual((self.effect(), self.pre.exists(), self.still()), ("lightning", False, 1))
        self.assertIn("cursor-fx lightning", self.sb.call_log())

    def test_saver_ending_while_quiet_is_on_leaves_the_effect_off_until_quiet_ends(self):
        self.ab("quiet", "on")
        self.ab("saver", "on")
        self.ab("saver", "off")
        self.assertEqual((self.effect(), self.pre.read_text().strip()), ("off", "lightning"))
        self.ab("quiet", "off")
        self.assertEqual((self.effect(), self.pre.exists()), ("lightning", False))

    def test_set_cursor_fx_under_saver_is_applied_now(self):  # spec bug 2
        self.ab("saver", "on")
        self.ab("set", "CURSOR_FX", "cyber")
        self.assertEqual(self.effect(), "cyber")
        self.assertIn("cursor-fx cyber", self.sb.call_log())

    def test_set_cursor_fx_under_quiet_waits_for_quiet_to_end(self):
        self.ab("quiet", "on")
        self.ab("set", "CURSOR_FX", "cyber")
        self.assertEqual((self.effect(), self.pre.read_text().strip()), ("off", "cyber"))
        self.ab("quiet", "off")
        self.assertEqual(self.effect(), "cyber")

    def test_cursor_fx_off_keeps_the_effect_off_through_theme_changes_and_saver(self):
        self.ab("set", "CURSOR_FX", "off")
        self.assertEqual(self.effect(), "off")
        self.hook("afterburn")
        self.assertEqual(self.effect(), "off")
        self.ab("saver", "on")
        self.ab("saver", "off")
        self.assertEqual(self.effect(), "off")

    def test_the_hook_switches_the_effect_under_saver(self):  # spec bug 2
        self.sb.write_state_text(self.sb.home / ".config/afterburn/afterburn.conf", "CURSOR_FX=neon\n")
        self.ab("saver", "on")
        r = self.sb.run(["/bin/bash", str(HOOK), "afterburn"])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual((self.effect(), self.pre.exists()), ("neon", False))

    def test_stale_hook_does_nothing_in_either_direction(self):
        self.sb.use_stubs(["afterburn"])
        bash = self.sb.bin / "bash"
        bash.unlink()
        bash.write_text('#!/bin/bash\necho "lock $*" >> "$SB/calls.log"\n')
        bash.chmod(0o755)
        self.sb.write_state_text(self.sb.state_dir / "lock-embers", "installed\n")
        self.sb.write_state_text(self.sb.state_dir / "prev-cursor-fx", "cyber\n")
        for current, stale in (("other", "afterburn"), ("afterburn", "other")):
            with self.subTest(current=current, stale=stale):
                self.sb.write_state_text(self.sb.home / ".local/state/omarchy/current/theme.name", current)
                self.sb.calls.write_text("")
                r = self.sb.run(["/bin/bash", str(HOOK), stale])
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertEqual(self.sb.call_log(), [])
                self.assertEqual(self.effect(), "lightning")
                self.assertEqual((self.sb.state_dir / "prev-cursor-fx").read_text(), "cyber\n")

    # --- what the hook records and restores (Codex review C3) ----------------------------------------
    def hook(self, theme):
        self.sb.write_state_text(self.sb.home / ".local/state/omarchy/current/theme.name", theme)
        r = self.sb.run(["/bin/bash", str(HOOK), theme])
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_a_pick_you_made_on_afterburn_stays_when_you_leave(self):
        self.hook("afterburn")
        self.assertEqual(self.effect(), "embers")
        self.start("neon")                      # you ran `cursor-fx neon`
        self.hook("nord")
        self.assertEqual(self.effect(), "neon")
        self.assertFalse((self.sb.state_dir / "prev-cursor-fx").exists())

    def test_a_failed_switch_records_nothing_as_ours(self):
        (self.sb.root / "cfx-fails").touch()
        self.hook("afterburn")
        self.assertEqual(self.effect(), "lightning")
        self.assertFalse((self.sb.state_dir / "cursor-fx-set").exists())

    def test_a_failed_restore_keeps_the_effect_to_restore(self):
        self.hook("afterburn")
        (self.sb.root / "cfx-fails").touch()
        self.hook("nord")
        self.assertEqual((self.sb.state_dir / "prev-cursor-fx").read_text().strip(), "lightning")
        (self.sb.root / "cfx-fails").unlink()
        self.hook("catppuccin")                 # the next switch away tries again
        self.assertEqual(self.effect(), "lightning")
        self.assertFalse((self.sb.state_dir / "prev-cursor-fx").exists())

    def test_an_indented_quoted_include_is_read_as_cursor_fx_reads_it(self):
        self.ghostty.write_text('font-size = 9\n  config-file = ?"cursor-effects/neon.conf"\n')
        self.hook("afterburn")
        self.assertEqual((self.sb.state_dir / "prev-cursor-fx").read_text().strip(), "neon")

    def test_leaving_while_fullscreen_holds_the_effect_off_still_restores_yours(self):
        self.hook("afterburn")
        self.ab("quiet", "on")
        self.assertEqual(self.effect(), "off")
        self.hook("nord")
        self.assertEqual(self.effect(), "lightning")

    def test_apply_recovers_a_cursor_left_off_by_interrupted_quiet_exit(self):
        self.sb.write_state_text(self.sb.state_dir / "quiet", "off\n")
        self.sb.write_state_text(self.pre, "lightning\n")
        self.ghostty.write_text("")
        self.ab("apply")
        self.assertEqual((self.effect(), self.pre.exists()), ("lightning", False))
        self.assertIn("cursor-fx lightning", self.sb.call_log())


if __name__ == "__main__":
    unittest.main()
