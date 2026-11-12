"""Quiet and saver each own one thing: quiet holds the cursor effect off (and saves it in cursor-pre-quiet),
saver only turns `cursor-fx subtle` on. They overlap in any order, and neither may leave the effect off."""
import unittest

from support import REPO, Sandbox

HOOK = REPO / "extras" / "afterburn-theme-set-hook"

# cursor-fx as far as these scripts can see it: the effect lives in Ghostty's config, `subtle` is a flag.
CURSOR_FX = r'''#!/bin/bash
echo "cursor-fx $*" >> "$SB/calls.log"
cfg="$HOME/.config/ghostty/config"
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

    def fx_calls(self, since=0):
        return [c for c in self.sb.call_log()[since:] if c.startswith("cursor-fx ") and c != "cursor-fx subtle"]

    def test_quiet_alone_saves_the_effect_and_puts_it_back(self):
        self.ab("quiet", "on")
        self.assertEqual((self.effect(), self.pre.read_text().strip()), ("off", "lightning"))
        self.ab("quiet", "off")
        self.assertEqual((self.effect(), self.pre.exists()), ("lightning", False))

    def test_saver_alone_never_holds_the_effect_off(self):
        self.ab("saver", "on")
        self.assertEqual((self.effect(), self.subtle(), self.pre.exists()), ("lightning", "on", False))
        self.ab("saver", "off")
        self.assertEqual((self.effect(), self.subtle(), self.pre.exists()), ("lightning", "off", False))

    def test_quiet_ending_while_saver_is_on_brings_the_effect_back(self):  # spec bug 1
        self.ab("saver", "on")
        self.ab("quiet", "on")
        self.assertEqual((self.effect(), self.pre.read_text().strip()), ("off", "lightning"))
        self.ab("quiet", "off")
        self.assertEqual((self.effect(), self.subtle(), self.pre.exists()), ("lightning", "on", False))
        self.assertIn("cursor-fx lightning", self.sb.call_log())

    def test_saver_ending_while_quiet_is_on_leaves_the_effect_off_until_quiet_ends(self):
        self.ab("quiet", "on")
        self.ab("saver", "on")
        self.ab("saver", "off")
        self.assertEqual((self.effect(), self.subtle(), self.pre.read_text().strip()), ("off", "off", "lightning"))
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

    def test_the_hook_switches_the_effect_under_saver(self):  # spec bug 2
        self.sb.write_state_text(self.sb.home / ".config/afterburn/afterburn.conf", "CURSOR_FX=neon\n")
        self.ab("saver", "on")
        r = self.sb.run(["/bin/bash", str(HOOK), "afterburn"])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual((self.effect(), self.pre.exists()), ("neon", False))

    def test_a_stale_pre_quiet_from_an_older_version_is_cleared_while_only_saver_is_on(self):
        self.sb.write_state_text(self.sb.state_dir / "saver", "on\n")
        self.sb.write_state_text(self.pre, "lightning\n")
        self.start("off")
        self.ab("apply")
        self.assertEqual((self.effect(), self.subtle(), self.pre.exists()), ("lightning", "on", False))


if __name__ == "__main__":
    unittest.main()
